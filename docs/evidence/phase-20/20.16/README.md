# 20.16 — el mutante de fuente que faltaba

Fecha: 2026-09-12. Rama `impl/20.16-20.17-mutantes-medicion` sobre `ad1333d`
(head del PR #308 abierto).

## Que faltaba

La DoD de 20.16 pide "mutantes y aislamiento". El aislamiento estaba y
discriminaba (`aislamiento: sibling intacta` en `tests/test_headless_close.sh`);
el mutante de fuente no existia: si alguien volvia al glob o aceptaba
`agents_seen` como recibo, ningun test se ponia rojo por construccion — el
mecanismo exacto que se colo en #303 y siguio vivo en #306.

## Lo que se agrego

Arnes de mutacion en `tests/test_headless_close.sh` siguiendo el idioma de
`tests/test_saikit_merge.sh:1302` (`mut_sed` + `correr_mutacion`): `cmp` canda
la mutacion vacua (un sed que no ata acredita en falso), `bash -n` que el
mutante parsee, control sano primero (un caso siempre-rojo atraparia por la
razon equivocada) y el caso tiene que ponerse rojo por COMPORTAMIENTO. La
copia mutada vive en un dir con `lib/` como symlink al repo (el launcher
resuelve su lib desde su propio `SCRIPT_DIR`; una copia suelta en TMPDIR
moriria en el source — un mutado que no corre no prueba nada).

Tres mutantes, cada uno rojo por comportamiento (demo en `mutantes-rojo.log`,
sano vs mutado, mismo escenario con mock):

1. `glob-mtime` — la resolucion por `session_id` sustituida por
   `ls -t .../*/harness-state.env | head -n 1`. Rojo en `mc_aislamiento`
   (hermana MAS NUEVA por `touch -t`, orden determinista):
   sano `rc=1 propia=gone hermana=live`; mutado `rc=1 propia=live
   hermana=gone` — borra la sesion equivocada con el mismo exit.
2. `agents-seen` — `agents_seen=.*implementer` en el estado cuenta como
   recibo. Rojo en `mc_leftover`: sano `rc=1 close_type=incomplete`;
   mutado `rc=0 close_type=forced`.
3. `host-rc0` — `|| [ "$HOST_RC" -eq 0 ]` junto a la condicion de recibo
   completo. Rojo en el mismo caso: sano `rc=1 incomplete`; mutado
   `rc=0 forced`.

De regalo del arnes: el mutante 1 solo lo atrapa la asercion sobre archivos
(el exit coincide), que es exactamente por lo que el caso revisa archivos y
no solo rc.

## Verde despues

`suite-verde.log`: `tests/test_headless_close.sh` → 17 PASS / 0 FAIL
(12 preexistentes + 2 argv por host + 3 mutantes atrapados). Cada mutante con
su guarda (`no cambio nada` / `no parsea`) y su control sano en verde antes
del rojo.

## Archivos

- `mutantes-rojo.log` — demo conductual sano-vs-mutado (el rojo citado).
- `suite-verde.log` — corrida verde del test con el arnes (los 3 atrapados).
- `run-identity.txt` — identidad de la corrida.
