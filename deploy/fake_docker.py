#!/usr/bin/env python3
"""Um `docker` de mentira para testar deploy/update.sh, sem Docker e sem rede (usado por test_update.sh).

Guarda o mundo em $STUB_DIR/world.json: imagens locais e do registry por serviço, os contêineres (id, serviço,
imagem, saúde) e a lista de imagens "doentes" (um contêiner delas nunca fica saudável). Reproduz só o que o
script usa: compose ps/pull/up, inspect, image inspect/prune, tag, stop, rm.
"""
import json, os, sys

S = os.environ["STUB_DIR"]
W = os.path.join(S, "world.json")
world = json.load(open(W))
args = sys.argv[1:]
with open(os.path.join(S, "calls"), "a") as f:
    f.write(" ".join(args) + "\n")
with open(os.path.join(S, "env"), "a") as f:
    f.write("COMPOSE_FILE=%s\n" % os.environ.get("COMPOSE_FILE", ""))


def save():
    json.dump(world, open(W, "w"))


def containers(svc):
    return [c for c in world["containers"] if c["svc"] == svc]


def healthy_serving():
    return [c for c in world["containers"] if c["svc"] == "plany" and c["health"] == "healthy"]


def new_container(svc, image):
    world["seq"] += 1
    # um contêiner novo só fica saudável se a imagem não é doente e a falha "tardia" não chegou
    bad = image in world["bad"]
    created = world.setdefault("created", 0) + 1
    world["created"] = created
    if world.get("bad_from_creation") and created == world["bad_from_creation"]:
        bad = True
    c = {"id": "c%d" % world["seq"], "svc": svc, "image": image, "health": "unhealthy" if bad else "healthy"}
    world["containers"].append(c)
    return c


def ref_service(ref):
    return "gateway" if "plany-gateway" in ref else "plany"


if args[0] == "compose":
    args = args[1:]
    cmd = args[0]
    if cmd == "ps":
        for c in containers(args[-1]):
            print(c["id"])
    elif cmd == "pull":
        if world.get("pull_fail"):
            sys.exit(1)
        world["local"] = dict(world["registry"])
        save()
    elif cmd == "up":
        flags, services, scale, i = set(), [], None, 1
        while i < len(args):
            a = args[i]
            if a in ("--wait-timeout",):
                i += 1
            elif a == "--scale":
                i += 1
                scale = int(args[i].split("=")[1])
            elif a.startswith("-"):
                flags.add(a)
            else:
                services.append(a)
            i += 1
        with open(os.path.join(S, "ups"), "a") as f:
            f.write("up %s\n" % " ".join(services))
        failed = False
        for svc in services:
            image = world["local"][svc]
            have = containers(svc)
            if "--no-recreate" in flags:
                target = scale if scale is not None else len(have)
                for _ in range(max(0, target - len(have))):
                    new_container(svc, image)
            else:
                if not have:
                    for _ in range(scale or (2 if svc == "plany" else 1)):
                        new_container(svc, image)
                else:
                    for c in have:
                        if c["image"] != image:  # recria no lugar, derrubando a antiga primeiro
                            world["containers"].remove(c)
                            new_container(svc, image)
            # --wait: falha se sobrar qualquer contêiner do serviço que não esteja saudável
            if any(c["health"] != "healthy" for c in containers(svc)):
                failed = True
        save()
        sys.exit(1 if failed else 0)
    else:
        sys.stderr.write("docker falso: compose %s\n" % cmd)
        sys.exit(99)
elif args[0] == "inspect":
    c = [x for x in world["containers"] if x["id"] == args[-1]][0]
    fmt = args[2]
    print(c["image"] if fmt == "{{.Image}}" else c["health"])
elif args[0] == "image":
    if args[1] == "inspect":
        print(world["local"][ref_service(args[-1])])
elif args[0] == "tag":
    world["local"][ref_service(args[2])] = args[1]
    with open(os.path.join(S, "tags"), "a") as f:
        f.write("tag\n")
    save()
elif args[0] in ("stop", "rm"):
    ids = [a for a in args[1:] if a.startswith("c")]
    for i in ids:
        remaining = [c for c in healthy_serving() if c["id"] != i]
        with open(os.path.join(S, "serving"), "a") as f:
            f.write("%d\n" % len(remaining))  # quantas réplicas saudáveis restam ao tirar esta
    if args[0] == "rm":
        world["containers"] = [c for c in world["containers"] if c["id"] not in ids]
        save()
else:
    sys.stderr.write("docker falso: comando inesperado: %s\n" % " ".join(args))
    sys.exit(99)
