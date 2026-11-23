.PHONY: all proto proto-go proto-dart proto-ts setup-clone

PROTO_DIR = shared/protos
DART_OUT = mobile/lib/shared/protos
TS_OUT = web/src/types

all: proto

proto: proto-go proto-dart proto-ts

proto-go:
	protoc --go_out=. $(PROTO_DIR)/*.proto

# -I makes the output flat: files land exactly in $(DART_OUT), not in $(DART_OUT)/shared/protos
proto-dart:
	mkdir -p $(DART_OUT)
	protoc -I$(PROTO_DIR) --dart_out=$(DART_OUT) $(PROTO_DIR)/*.proto

proto-ts:
	mkdir -p $(TS_OUT)
	protoc --ts_proto_out=$(TS_OUT) --ts_proto_opt=outputServices=generic-definitions,esModuleInterop=true $(PROTO_DIR)/*.proto

# Once per clone: the pre-push hook that refuses a main or dev without its own files (.githooks/pre-push) and the `ours`
# merge driver that .gitattributes names. See .forgejo/scripts/check-branch-files.sh.
setup-clone:
	git config core.hooksPath .githooks
	git config merge.ours.driver true
	@echo "clone configurado: hook pre-push e merge driver 'ours' ativos"
