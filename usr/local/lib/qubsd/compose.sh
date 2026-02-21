#!/bin/sh

# High level aggregator that bootstraps the cell, validates it, and writes the initial runtime
compose_runtime_context() {
    local _fn="compose_runtime_context" _cell="$1" _pfx="$2"
    trap_push "rm_rt_ctx"

    bootstrap_cell_ctx $_cell $_pfx  || eval $(THROW 1 _generic "Cell bootstrap failed")
    ctx_validate_params $_cell $_pfx || eval $(THROW 1 _generic "Cell validation failed")
    ctx_runtime_init $_cell $_pfx    || eval $(THROW 1 _generic "Failed to write runtime context")
}

# Return the most recent rootenv snapshot possible. Must avoid running rootenv and stale data
resolve_rootenv_snapname() {
    local _fn="resolve_rootenv_snapname" _dset="$1"
    local _rootsnaps _psmod _lstart _line _snap _date _timestamp _now

    # Try existing ROOTSNAPS. If unavail, grab _dset snaps. Then rev order for while/read loop
    [ $ROOTSNAPS ] && _rootsnaps=$(echo "$ROOTSNAPS" | grep $_dset)
    [ -z "$_rootsnaps" ] && unset $ROOTSNAPS && query_rootsnaps $_dset
    _rootsnaps=$(echo "$ROOTSNAPS" | grep $_dset \
                | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}')

    # For safety, running ROOTENV snapshot should be taken from before it was started
    if _psmod="-p $(hush pgrep -f "bhyve: $ROOTENV")" || _psmod="-J $(hush jls -j $ROOTENV jid)" ; then
        _lstart=$(ps -o lstart $_psmod | tail -1 | xargs -I@ date -j -f "%a %b %d %T %Y" @ +"%s")

        while IFS= read -r _line ; do
            # Extract snapshot, date string, and covert the timestamp
            _snap=$(echo "$_line" | awk '{print $1}')
            _date=$(echo "$_line" | awk '{print $3, $4, $5, $6, $7}')
            _timestamp=$(date -j -f "%a %b %d %H:%M %Y" "$_date" +"%s")

            # Compare data, continue or break
            [ "$_lstart" -gt "$_timestamp" ] && echo $_snap && return 0
        done << EOF
$_rootsnaps
EOF

    else
        # Ensure against stale rootenv snapshot by checking 'written'
        _snap=$(echo "$_rootsnaps" | head -1)
        [ "$(echo $_snap | awk '{print $2}')" = "0" ] && echo $_snap && return 0

        # Last avail rootenv snap is in fact stale (or non-existent). Prepare a new one.
        _now=$(date +%s)
        echo "$_dset@${_now}" && return 2   # '2' tells caller to perform a new snapshot
    fi
}

# Return the most recent rootenv snapshot possible. Must avoid running rootenv and stale data
resolve_persist_snapname() {
    local _fn="resolve_persist_snapname" _dset="$1"
    local _prstsnaps _psmod _lstart _line _snap _date _timestamp _now

    # Try existing PRSTSNAPS. If unavail, grab _dset snaps. Then rev order for while/read loop
    [ $PRSTSNAPS ] && _prstsnaps=$(echo "$PRSTSNAPS" | grep $_dset)
    [ -z "$_prstsnaps" ] && unset $PRSTSNAPS && query_prstsnaps $_dset
    _prstsnaps=$(echo "$PRSTSNAPS" | grep $_dset \
                | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}')

    # For safety, running ROOTENV snapshot should be taken from before it was started
    if _psmod="-p $(hush pgrep -f "bhyve: $ROOTENV")" || _psmod="-J $(hush jls -j $ROOTENV jid)" ; then
        _lstart=$(ps -o lstart $_psmod | tail -1 | xargs -I@ date -j -f "%a %b %d %T %Y" @ +"%s")

        while IFS= read -r _line ; do
            # Extract snapshot, date string, and covert the timestamp
            _snap=$(echo "$_line" | awk '{print $1}')
            _date=$(echo "$_line" | awk '{print $3, $4, $5, $6, $7}')
            _timestamp=$(date -j -f "%a %b %d %H:%M %Y" "$_date" +"%s")

            # Compare data, continue or break
            [ "$_lstart" -gt "$_timestamp" ] && echo $_snap && return 0
        done << EOF
$_prstsnaps
EOF

    else
        # Ensure against stale rootenv snapshot by checking 'written'
        _snap=$(echo "$_prstsnaps" | head -1)
        [ "$(echo $_snap | awk '{print $2}')" = "0" ] && echo $_snap && return 0

        # Last avail rootenv snap is in fact stale (or non-existent). Prepare a new one.
        _now=$(date +%s)
        echo "$_dset@${_now}" && return 2   # '2' tells caller to perform a new snapshot
    fi
}

compose_snapshot_context() {
    local _fn="compose_snapshot_context"
}
