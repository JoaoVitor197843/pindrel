// Package testnaming guards a convention the CI depends on: every Go test that needs the real database
// (it loads backend/.env or opens a connection, directly or through a helper) is named TestDB_*. The CI
// runner has no Postgres and no .env, so .forgejo/workflows/backend.yml skips exactly `^TestDB_`; a database
// test with any other name would pass locally and break the pipeline.
package testnaming_test

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

const dbPrefix = "TestDB_"

// what makes a function "need the database": a call to one of these, or to a helper that does.
// config.Load is NOT here: the config tests call it with t.Setenv, no database and no .env involved;
// whoever needs the real configuration reads backend/.env first, with godotenv.Load.
var dbCalls = map[string]bool{
	"database.NewConnection": true,
	"godotenv.Load":          true,
	"pgxpool.New":            true,
	"pgxpool.NewWithConfig":  true,
}

type file struct {
	name string
	src  any // string or nil (read from disk)
}

// violations returns the tests of one directory that need the database but are not named TestDB_*.
func violations(t *testing.T, files []file) []string {
	t.Helper()
	fset := token.NewFileSet()
	funcs := map[string]*ast.FuncDecl{}
	for _, f := range files {
		parsed, err := parser.ParseFile(fset, f.name, f.src, 0)
		if err != nil {
			t.Fatalf("parse %s: %v", f.name, err)
		}
		for _, decl := range parsed.Decls {
			if fn, ok := decl.(*ast.FuncDecl); ok && fn.Recv == nil && fn.Body != nil {
				funcs[fn.Name.Name] = fn
			}
		}
	}

	// calls[name] = what the function calls, as `pkg.Func` or a bare same-directory function name
	calls := map[string][]string{}
	for name, fn := range funcs {
		ast.Inspect(fn.Body, func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok {
				return true
			}
			switch fun := call.Fun.(type) {
			case *ast.SelectorExpr:
				if pkg, ok := fun.X.(*ast.Ident); ok {
					calls[name] = append(calls[name], pkg.Name+"."+fun.Sel.Name)
				}
			case *ast.Ident:
				calls[name] = append(calls[name], fun.Name)
			}
			return true
		})
	}

	needsDB := map[string]bool{}
	for changed := true; changed; {
		changed = false
		for name := range funcs {
			if needsDB[name] {
				continue
			}
			for _, c := range calls[name] {
				if dbCalls[c] || needsDB[c] {
					needsDB[name], changed = true, true
					break
				}
			}
		}
	}

	var bad []string
	for name := range funcs {
		if strings.HasPrefix(name, "Test") && needsDB[name] && !strings.HasPrefix(name, dbPrefix) {
			bad = append(bad, name)
		}
	}
	sort.Strings(bad)
	return bad
}

func TestDBTestsAreNamedTestDB(t *testing.T) {
	root := ".." // backend/internal
	dirs := map[string][]file{}
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !d.IsDir() && strings.HasSuffix(path, "_test.go") {
			dir := filepath.Dir(path)
			dirs[dir] = append(dirs[dir], file{name: path})
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(dirs) < 5 {
		t.Fatalf("found test files in only %d directories under %s: wrong working directory?", len(dirs), root)
	}
	for dir, files := range dirs {
		if bad := violations(t, files); len(bad) > 0 {
			t.Errorf("%s: tests that need the database must be named %s*, rename: %s", dir, dbPrefix, strings.Join(bad, ", "))
		}
	}
}

// The guard itself: it must catch what it is for and leave everything else alone.
func TestGuard_Detects(t *testing.T) {
	src := func(body string) []file {
		return []file{{name: "x_test.go", src: "package x\nimport \"testing\"\n" + body}}
	}
	cases := []struct {
		name string
		code string
		want []string
	}{
		{"direct .env load", `func TestA(t *testing.T) { godotenv.Load("../../.env") }`, []string{"TestA"}},
		{"config.Load with t.Setenv is not a DB test", `func TestA(t *testing.T) { t.Setenv("A", "1"); config.Load() }`, nil},
		{"direct connection", `func TestA(t *testing.T) { database.NewConnection(nil, nil) }`, []string{"TestA"}},
		{"through a helper", `func setup() { godotenv.Load("x") }
func TestA(t *testing.T) { setup() }`, []string{"TestA"}},
		{"through two helpers", `func a() { godotenv.Load("x") }
func b() { a() }
func TestA(t *testing.T) { b() }`, []string{"TestA"}},
		{"already named TestDB_", `func TestDB_A(t *testing.T) { godotenv.Load("x") }`, nil},
		{"pure test", `func TestA(t *testing.T) { _ = 1 + 1 }`, nil},
		{"helper that is not a test", `func setup() { godotenv.Load("x") }`, nil},
		{"only the DB ones are reported", `func TestA(t *testing.T) { godotenv.Load("x") }
func TestB(t *testing.T) {}
func TestC(t *testing.T) { pgxpool.NewWithConfig(nil, nil) }`, []string{"TestA", "TestC"}},
		{"method named like a helper is not a call to it", `func TestA(t *testing.T) { x.Load() }`, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := violations(t, src(c.code))
			if strings.Join(got, ",") != strings.Join(c.want, ",") {
				t.Fatalf("got %v, want %v", got, c.want)
			}
		})
	}
}
