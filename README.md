# GHGrabber

A small scraper for GitHub that grew.

## Requires

- GNU parallel
- GNU AWK 

```
sudo apt install parallel gawk 
```
## Example usage

```
./grab.sh --repo-list=repos/repo.list.00 --output-dir=data --processes=4
```

## Input format

The script requires a file containing a repository list: one repository per
line. Each repository is specified as `USER/PROJECT`. For example:

```
PRL-PRG/ghgrabber
torvalds/linux
JuliaLang/julia
kuwisdelu/matter
```

## Modules

The script extracts several distinct datasets. We call a subscript responsible
for extracting a specific subset of data a module. The script has the following
modules:

- `commit_metadata` extract the metadata about each commit, consisting of its hash, the credentials of its authors, and its tag.
- `commit_file_modification_info` extracts data informing about file modifications à la `numstat`, consisting of the hash of the modifying commit, the number of added and deleted lines, the filename, and a new filename (in case of renaming).
- `commit_file_modification_hashes` extracts data informing about file modifications à la `raw`, conisting of the hash of the modifying commit, the hash of the file, the status code describing a modification type, a filename, and a new filename (in case of renaming).
- `commit_comments` extracts commit comments.
- `commit_parents` extracts the hashes of the parents of commits in the form: commit hash, parent hash.
- `commit_repositories`: extracts the information about which repository a particular commit comes from.
- `repository_info`: extracts the id, user, and project name of a repository.
- `submodule_history`: extracts the modification history of the .gitmodules file.
- `submodule_museum`: extracts all of the versions of the .gitmodules file.

The script can be run with only specific modules:

```
./grab.sh --repo-list=repos/repo.list.00 --output-dir=data --processes=4 --modules=commit_metadata,commit_file_modification_info
```

## Output

The script extracts several distinct sets of information. Each of these is
saved in a separate subdirectory in the output directory.

In addition the script outputs the following files:

- `timing.csv` contains performance information from downloading each repository; it contains the credentials of the repo, the timestamp when downloading started, the elapsed processing time, the status of the processor, the number of commits, files, and the size of the repository on disk.
- `spec_cert.conf` contains the information about the configuration of the script when it was running, including version, no. of processes, and input file.
- `sequence.val` is a file used by the script to generate project ids. If it is present in the directory, additional repositories may be downloaded into that directory and the ids will continue being unique.

After the script finishes running, the entire output directory is compressed as tar.gz, for convenience (mine).
