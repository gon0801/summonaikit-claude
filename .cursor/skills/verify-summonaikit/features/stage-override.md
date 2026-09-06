# Stage a hook by project override

Stage a hook by project override installs the gate hook into one disposable
git lab via `tools/stage-override.sh`. The file that ran matches the source
hash and gate state stays under the lab. A synthetic external profile is left
intact. The tool refuses an unowned destination. Cleanup is scoped to this
run. This drive never installs an override or trust on a live operator session.

## Sub-features

- `stage-prepare` writes the override into a disposable git fixture and measures that the registered command prefers it.
- `stage-hook-hash` runs that staged hook and requires its file hash to match the repo source.
- `stage-state-lab` finds harness state only under the lab, not under the synthetic profile.
- `stage-profile-intact` leaves the synthetic external profile sentinel and global hook bytes unchanged.
- `stage-ownership` refuses to overwrite a destination without the ownership marker and leaves that file intact.
- `stage-cleanup` restores prior lab state after measurement and does not delete a foreign neighbor or keep-dir.
- `stage-no-live` keeps dest and settings under the run temp; it does not write trust or override on a live session.

## How to get to it (user POV)

- Run `bash tools/stage-override.sh <disposable-git-repo>` so the project override is preferred over the profile hook.
- Open a new session in that repo: a prompt with `-saikit` arms the lab hook; state appears under `<repo>/.claude/hooks/state/`.
- Do not point this tool at a live operator profile or add project trust there.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit launch` created an isolated HOME.
- Staging runs only on a disposable git fixture. Settings are synthetic. The live operator session is not used.

- Case `stage-prepare`: action Stage the override on a new git fixture; command `control-summonaikit drive stage-override`; observable dest exists, bytes match the source, and the tool reports it measured the preference.
- Case `stage-hook-hash`: action Run the staged hook with an armed payload; command `control-summonaikit drive stage-override`; observable the executed dest hash equals the source hash.
- Case `stage-state-lab`: action Inspect state after that run; command `control-summonaikit drive stage-override`; observable state files under the lab and none new under the synthetic profile.
- Case `stage-profile-intact`: action Re-read the planted profile sentinel and global hook; command `control-summonaikit drive stage-override`; observable both checksums unchanged.
- Case `stage-ownership`: action Stage over a dest without the ownership marker; command `control-summonaikit drive stage-override`; observable a non-zero refuse and unchanged foreign bytes.
- Case `stage-cleanup`: action Re-read prior lab state and a neighbor after measurement; command `control-summonaikit drive stage-override`; observable prior content restored, neighbor and foreign keep-dir intact.
- Case `stage-no-live`: action Confirm dest and settings paths; command `control-summonaikit drive stage-override`; observable both under the run temp and no live-session install.

## Gotchas

- A directory that is not a git repo is a refuse: the registered command resolves the override with `git rev-parse --show-toplevel`.
- Measurement deletes its own state and restores whatever was already in the lab. A second real turn must start clean or with that prior content, not armed by the measurement.
- Do not install this override or add project trust on a live operator session. The skill only drives isolated HOME and fixture temps.
