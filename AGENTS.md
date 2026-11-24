# Tuna Hue agent instructions

When referring to files in user-facing messages, identify the owning repository as the outer `tuna-hue` repo or the inner `TunaExtensions` extension repo. Label file links or file lists accordingly, especially when both repos have a file with the same name.

After committing or pulling changes in `TunaExtensions`, commit the updated submodule pin in the outer `tuna-hue` repo. Before pushing the outer commit, make sure the pinned revision is available from the submodule's configured remote.
