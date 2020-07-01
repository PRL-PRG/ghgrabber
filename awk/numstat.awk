@include "escape.awk"

# an AWK script that transforms the output of git-log into a CSV-like output
# containing the information about which file was modified by which commit and
# how
BEGIN {
    # expect the following record format:
    #
    #   $1\n\n$2\n\n\n
    #
    # where $1 is the hash of the commit and $2 is a multi-line description of
    # which files were modified by the commit and how (numstat), eg:
    #
    #   1 0   include/linux/interrupt.h
    #   4 0   kernel/irq/affinity.c
    #   8 5   kernel/irq/irqdesc.c
    #
    # since the filenames get complicated in cases of renaming, $2 should also include 
    # the output from raw as well, containing hash information, modification info, and 
    # filenames, eg:
    # 
    # :100644 000000 c861ffa9ae998c50c982d5432cdaa0eb27738c1c 0000000000000000000000000000000000000000 D      api_grab.r
    # :100755 000000 8b659d68277ec8417116cbb8865900db5a065675 0000000000000000000000000000000000000000 D      comment.awk
    # :100644 000000 1f284d5ce2ec0cadc21a13228b2bf088f603311f 0000000000000000000000000000000000000000 D      files_changes_only.awk
    # :100644 000000 d9bd25814d36d1efbb53ed00f6ee0b462405f329 0000000000000000000000000000000000000000 D      githubapi.r
    # :100755 100755 09f1b7326254f00ff98c2426c9fc64dbc1652502 aac139e1ffd50ccbebd59a2192956ede10229e02 M      grab.sh
    # :100755 000000 0579880c328da8c2b80dc128164f574b1bca1211 0000000000000000000000000000000000000000 D      numstat.awk
    # :100644 000000 14f84e205c296e705c26f1a541c1c72830787b89 0000000000000000000000000000000000000000 D      retrieve_starred_repos.r
    # :100644 000000 b1755b53d248aa65d144eca3e102e1420ac2a22b 0000000000000000000000000000000000000000 D      schema.sql
    # :100644 100644 de03518b6444cff4d9238663edf2cc81e59efd63 f21fad67b78973ee6e82766a3f5e1635275ea261 R071   test/child-process-follows.js   test/child-process-follow.js
    #
    # assumption: there's one line of numstat for every line of raw.
    FS="\n\n"; 
    RS="\n\n\n"; 

    # format output so that fields are separated by commas, records are
    # separated by new lines
    OFS=",";
    ORS="\n";

    # output header
    print quote("hash"), quote("added lines"), quote("deleted lines"), quote("filename"), quote("old filename")
} 

# for each input record
{
    # first split the second field into separate lines
    split($2, stats, "\n");

    numstat_length = 0;
    raw_length = 0;

    # split into numstat and raw inputs
    for(ix in stats) {
        line = stats[ix];
        if (line ~ /^[ \t]*$/) {
            continue;
        }
        if (line ~ "^[ \t]*:") {
            raw[raw_length++] = line;
        } else {    
            numstat[numstat_length++] = line;
        }
    }

    for (ix = 0; ix < numstat_length; ix++) {
        split(raw[ix], raw_columns, /[\t]+/);
        split(numstat[ix], numstat_columns, /[\t]+/);

        if (numstat_columns[1] == "-") {
            added = "";
        } else {
            added = numstat_columns[1];        
        }

        if (numstat_columns[2] == "-") {
            deleted = "";
        } else {
            deleted = numstat_columns[2];        
        }

        if (length(raw_columns) == 2) {
            print $1, added, deleted, quote_if_needed(raw_columns[2]), "";
        } else if (length(raw_columns) == 3) {
            print $1, added, deleted, quote_if_needed(raw_columns[3]), quote_if_needed(raw_columns[2]);
        } else {
            print $1, added, deleted, quote_if_needed(raw_columns[3]), quote_if_needed(raw_columns[2]), 
                  "# FORMAT ERROR: " length(raw_columns) " fields in line " raw[ix] " (expected 2 or 3)";
        }
    }
}
