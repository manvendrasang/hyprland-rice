#!/usr/bin/env bash

hyprx_install_packages_run() {
    # No banner - the engine prints one for the whole run. See the note in
    # validator.sh.
    hyprx_ui_section "Installing packages"

    HYPRX_INSTALL_INSTALLED=()
    HYPRX_INSTALL_SKIPPED=()
    HYPRX_INSTALL_FAILED=()

    HYPRX_INSTALL_START_TIME=$(date +%s)

    hyprx_recovery_save_state

    local pkg status

    # One transaction per source instead of one per package. The per-package loop
    # below still runs, but it now finds everything already installed and
    # short-circuits, so the user still sees each package reported.
    #
    # The queue is filtered to what is actually missing first: re-running an
    # install must be a no-op, not a full re-resolve of 136 packages.
    local -a todo=()
    for pkg in "${HYPRX_INSTALL_QUEUE[@]}"; do
        if hyprx_pkg_installed "$pkg"; then
            HYPRX_INSTALL_SKIPPED+=("$pkg")
            hyprx_recovery_mark_complete "$pkg"
        else
            todo+=("$pkg")
        fi
    done

    # Remember what the batch was asked to install. After it succeeds those
    # packages answer "already installed" to hyprx_pkg_install, which would
    # report them as SKIPPED - so the summary would say a package was skipped
    # in the same run that installed it.
    declare -A batch_installed=()

    if (( ${#todo[@]} > 0 )); then
        if hyprx_pkg_install_many "${todo[@]}"; then
            for pkg in "${todo[@]}"; do
                batch_installed["$pkg"]=1
            done
        fi
        # A failed batch falls through to the per-package loop, which retries
        # each one individually and reports the real failures.
    fi

    for pkg in "${HYPRX_INSTALL_QUEUE[@]}"; do
        hyprx_ui_info "Installing $pkg"

        # hyprx_pkg_install signals "already installed" with 10, which would
        # read as a failure.
        #
        # This used to be `set +e; hyprx_pkg_install; status=$?; set -e`.
        # That turned errexit ON for the rest of the process and left it on:
        # bin/hyprx deliberately runs without -e (see its header), so the very
        # next unguarded failing command aborted the whole install - which was
        # hyprx_pkg_install inside the retry loop below. One package failing
        # twice killed the retry ladder, the summary, the failure-log summary,
        # deploy, the snapshot and the report, and left install.state behind
        # for the next run to resume from.
        #
        # `if` keeps errexit untouched and is the only construct that preserves
        # a non-zero status without tripping it.
        if hyprx_pkg_install "$pkg"; then
            status=0
        else
            status=$?
        fi

        case "$status" in
            0)
                hyprx_ui_success "$pkg"
                HYPRX_INSTALL_INSTALLED+=("$pkg")
                hyprx_recovery_mark_complete "$pkg"
                ;;
            # Installed by the batch above, so it answers "already present" here.
            10)
                if [[ -n "${batch_installed[$pkg]:-}" ]]; then
                    hyprx_ui_success "$pkg"
                    HYPRX_INSTALL_INSTALLED+=("$pkg")
                else
                    hyprx_ui_info "$pkg already installed."
                    HYPRX_INSTALL_SKIPPED+=("$pkg")
                fi
                hyprx_recovery_mark_complete "$pkg"
                ;;
            *)
                hyprx_ui_error "$pkg"
                HYPRX_INSTALL_FAILED+=("$pkg")
                hyprx_failure_logger_log "$pkg" "Installation failed"
                ;;
        esac
    done

    if (( ${#HYPRX_INSTALL_FAILED[@]} > 0 )); then
        hyprx_ui_divider
        hyprx_ui_warn "Retrying failed packages..."
        hyprx_retry_failed_packages
    fi

    HYPRX_INSTALL_END_TIME=$(date +%s)
    HYPRX_INSTALL_DURATION=$((HYPRX_INSTALL_END_TIME - HYPRX_INSTALL_START_TIME))

    # Retry ladder finished: whatever is still in FAILED genuinely failed.
    # The summary, report and doctor all need to be able to tell "everything
    # went in" from "some of it did not", which they previously could not.
    HYPRX_INSTALL_PARTIAL=false
    (( ${#HYPRX_INSTALL_FAILED[@]} > 0 )) && HYPRX_INSTALL_PARTIAL=true
    export HYPRX_INSTALL_PARTIAL

    hyprx_ui_divider
    hyprx_ui_success "Installation Summary"
    echo

    printf "%-12s : %d\n" "Installed" "${#HYPRX_INSTALL_INSTALLED[@]}"
    printf "%-12s : %d\n" "Skipped"   "${#HYPRX_INSTALL_SKIPPED[@]}"
    printf "%-12s : %d\n" "Failed"    "${#HYPRX_INSTALL_FAILED[@]}"
    printf "%-12s : %02d:%02d\n" \
        "Duration" \
        "$((HYPRX_INSTALL_DURATION / 60))" \
        "$((HYPRX_INSTALL_DURATION % 60))"
    echo

    if (( ${#HYPRX_INSTALL_FAILED[@]} > 0 )); then
        hyprx_ui_warn "Packages still failing"
        echo

        for pkg in "${HYPRX_INSTALL_FAILED[@]}"; do
            echo " • $pkg"
        done

        echo
        hyprx_ui_warn "Failure log"
        echo " $HYPRX_FAILURE_LOG_OVERRIDE"

        hyprx_failure_logger_summary
    else
        hyprx_ui_success "All packages installed successfully."
    fi

    hyprx_recovery_clear_state

    # This used to fall off the end and return the status of
    # hyprx_recovery_clear_state - always 0. So engine.sh saw a clean install
    # and printed "Installation completed successfully" directly after listing
    # twelve failed packages. Return an explicit code instead: 0 only when
    # nothing is left in FAILED.
    if (( ${#HYPRX_INSTALL_FAILED[@]} > 0 )); then
        return 1
    fi

    return 0
}
