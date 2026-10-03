#!/usr/bin/env bash

# Font installation.
#
# Caudex is the only font this rice uses. It is fetched directly from the
# upstream Google Fonts repository rather than installed as a package, because
# the only Arch option - ttf-google-fonts-git - depends on 22 other font
# packages (noto-*, adobe-source-*, roboto, ubuntu, fira, lato ...) and pulls
# in the entire Google catalogue. That is hundreds of megabytes for four files.
#
# Each file is pinned by SHA256. A mismatch is a hard failure, not a warning:
# the point of fetching over the network is that the bytes are verified, and a
# silent fallback would make that meaningless.
#
# Fonts land in ~/.local/share/fonts/hyprx/, which fontconfig already scans.
# That is per-user, so no root is required and nothing outside $HOME changes.

HYPRX_FONT_DIR="${HYPRX_FONT_DIR:-${HYPRX_TARGET_HOME:-$HOME}/.local/share/fonts/hyprx}"
HYPRX_FONT_SOURCE="${HYPRX_FONT_SOURCE:-https://raw.githubusercontent.com/google/fonts/main/ofl/caudex}"

# file | expected sha256
#
# Pins are the four static Caudex faces at the upstream revision recorded here.
# All four are needed: Regular/Bold for the UI, Italic/BoldItalic because GTK
# synthesises neither and a bold-italic label would otherwise render as a
# slanted, wrong-weight fallback.
#
# The list can be overridden through HYPRX_FONT_SPEC (space-separated
# "file|sha256" pairs) purely so tests can exercise the fetch-and-verify path
# against a local file:// URL instead of the network. Production never sets it;
# `tests/run_tests.sh` asserts the override is what it expects and that the
# shipped default is the four real pins.
HYPRX_FONT_SPEC="${HYPRX_FONT_SPEC:-Caudex-Regular.ttf|dbb493e1adc50aaec52071535e6fccf4176793c79545f54d95a812cbfb85169b Caudex-Bold.ttf|880fb67901ce94573ed0262d152b87115a08f928c72fc6c1101375a1223d390a Caudex-Italic.ttf|ffa47f625d746e7b75c2306b7572f22561e1d73312a375772325c98213e0a4f9 Caudex-BoldItalic.ttf|78440e8ab6730581ac71fe780ad2fa15ba15d240313028678e404ace4e70eb20}"

HYPRX_FONT_FILES=()
hyprx_fonts_parse_spec() {
    HYPRX_FONT_FILES=()
    local -a entries=()
    read -r -a entries <<<"$HYPRX_FONT_SPEC"
    local entry
    for entry in "${entries[@]}"; do
        [[ "$entry" == *"|"* ]] || continue
        HYPRX_FONT_FILES+=("$entry")
    done
}
hyprx_fonts_parse_spec

HYPRX_FONTS_INSTALLED=()
HYPRX_FONTS_FAILED=()

# Size of the source file, when it is local. Only used for the pre-hash sanity
# check; a remote fetch has no known size, so an empty answer skips that check
# and relies on the hash alone (which is the stronger guarantee anyway).
hyprx_font_expected_bytes() {
    local name="$1" path

    case "$HYPRX_FONT_SOURCE" in
        file://*)
            path="${HYPRX_FONT_SOURCE#file://}/$name"
            [[ -f "$path" ]] || return 0
            wc -c <"$path" 2>/dev/null | tr -d ' '
            ;;
        *)
            printf ''
            ;;
    esac
}

hyprx_fonts_sha256() {
    local file="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" 2>/dev/null | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" 2>/dev/null | awk '{print $1}'
    else
        printf ''
    fi
}

hyprx_fonts_already_present() {
    local entry name want have
    local dir="$1"

    [[ -d "$dir" ]] || return 1

    for entry in "${HYPRX_FONT_FILES[@]}"; do
        name="${entry%%|*}"
        want="${entry##*|}"

        [[ -f "$dir/$name" ]] || return 1

        have="$(hyprx_fonts_sha256 "$dir/$name")"
        # An unverifiable hash is not a match - re-fetch rather than assume.
        [[ -n "$have" && "$have" == "$want" ]] || return 1
    done

    return 0
}

# curl or wget, whichever exists. Neither is a HyprX dependency in its own
# right - coreutils does not ship either - but both are near-universal on Arch
# and one of them is required to fetch anything.
hyprx_fonts_downloader() {
    if command -v curl >/dev/null 2>&1; then
        printf 'curl'
    elif command -v wget >/dev/null 2>&1; then
        printf 'wget'
    else
        printf ''
    fi
}

hyprx_fonts_install() {
    hyprx_ui_section "Fonts"

    HYPRX_FONTS_INSTALLED=()
    HYPRX_FONTS_FAILED=()

    local dir="$HYPRX_FONT_DIR"

    if hyprx_fonts_already_present "$dir"; then
        hyprx_ui_success "Caudex already installed and verified ($dir)"
        return 0
    fi

    if hyprx_util_dry_run; then
        local entry
        for entry in "${HYPRX_FONT_FILES[@]}"; do
            hyprx_util_would "download and verify ${entry%%|*} -> $dir"
        done
        hyprx_util_would "run fc-cache -f"
        return 0
    fi

    local fetch
    fetch="$(hyprx_fonts_downloader)"

    if [[ -z "$fetch" ]]; then
        hyprx_ui_error "Neither curl nor wget is available - cannot fetch Caudex."
        hyprx_ui_info "Install one (pacman -S curl) and re-run, or place the four"
        hyprx_ui_info "Caudex TTFs in $dir by hand."
        return 1
    fi

    if ! hyprx_util_command_exists fc-cache; then
        hyprx_ui_warn "fc-cache not found - fonts will be installed but may not"
        hyprx_ui_warn "be visible until fontconfig is next rebuilt (pacman -S fontconfig)"
    fi

    mkdir -p "$dir" || {
        hyprx_ui_error "Could not create $dir"
        return 1
    }

    # Staged, then moved into place, so an interrupted run cannot leave a
    # half-written file that fontconfig would try to parse.
    local tmp
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/hyprx-fonts.XXXXXX")" || {
        hyprx_ui_error "Could not create a staging directory"
        return 1
    }

    local entry name want got expect_bytes
    for entry in "${HYPRX_FONT_FILES[@]}"; do
        name="${entry%%|*}"
        want="${entry##*|}"
        expect_bytes="$(hyprx_font_expected_bytes "$name")"

        if [[ "$fetch" == "curl" ]]; then
            # --fail so an HTTP 404 is an error rather than a saved error page
            # that would then fail the hash check with a confusing message.
            # A file:// source needs -f off or curl rejects the transfer, so
            # the flags are chosen per scheme.
            if [[ "$HYPRX_FONT_SOURCE" == file://* ]]; then
                curl -sSL --max-time 60 -o "$tmp/$name" "$HYPRX_FONT_SOURCE/$name" 2>/dev/null || {
                    rm -rf "$tmp"
                    hyprx_ui_error "Download failed: $name"
                    return 1
                }
            else
                curl -fsSL --max-time 60 -o "$tmp/$name" "$HYPRX_FONT_SOURCE/$name" 2>/dev/null || {
                    rm -rf "$tmp"
                    hyprx_ui_error "Download failed: $name"
                    hyprx_ui_info "Check connectivity, or fetch it manually from:"
                    hyprx_ui_info "  $HYPRX_FONT_SOURCE/$name"
                    return 1
                }
            fi
        else
            wget -q --timeout=60 -O "$tmp/$name" "$HYPRX_FONT_SOURCE/$name" 2>/dev/null || {
                rm -rf "$tmp"
                hyprx_ui_error "Download failed: $name"
                return 1
            }
        fi

        # Size first: it is a cheap sanity check that rules out an HTML error
        # page before the hash comparison produces a wall of hex.
        if [[ -n "$expect_bytes" ]]; then
            local actual_bytes
            actual_bytes="$(wc -c <"$tmp/$name" 2>/dev/null | tr -d ' ')"
            if [[ "$actual_bytes" != "$expect_bytes" ]]; then
                rm -rf "$tmp"
                hyprx_ui_error "Size mismatch for $name: got $actual_bytes, expected $expect_bytes"
                return 1
            fi
        fi

        got="$(hyprx_fonts_sha256 "$tmp/$name")"
        if [[ -z "$got" ]]; then
            rm -rf "$tmp"
            hyprx_ui_error "No sha256 tool available (sha256sum or shasum) - refusing to install unverified fonts"
            return 1
        fi

        if [[ "$got" != "$want" ]]; then
            rm -rf "$tmp"
            hyprx_ui_error "Checksum mismatch for $name"
            hyprx_ui_info "  expected $want"
            hyprx_ui_info "  got      $got"
            hyprx_ui_info "Upstream may have changed. Re-pin in lib/installer/fonts.sh"
            hyprx_ui_info "only if you have checked the new file is genuinely Caudex."
            return 1
        fi

        mv -f "$tmp/$name" "$dir/$name"
        HYPRX_FONTS_INSTALLED+=("$name")
        if [[ -n "$expect_bytes" ]]; then
            hyprx_ui_success "$name ($(hyprx_state_human "$expect_bytes"))"
        else
            hyprx_ui_success "$name"
        fi
    done

    rm -rf "$tmp"

    if command -v fc-cache >/dev/null 2>&1; then
        # Scoped to our own directory rather than a full -f rebuild of every
        # font on the system. if/else rather than &&/|| so a failure can never
        # be reported as a success - SC2015 is enabled for exactly this shape.
        if fc-cache -f "$dir" >/dev/null 2>&1; then
            hyprx_ui_success "Font cache updated"
        else
            hyprx_ui_warn "fc-cache failed - fonts may need a logout/login to appear"
        fi
    fi

    echo
    hyprx_ui_success "Installed ${#HYPRX_FONTS_INSTALLED[@]} Caudex file(s) to $dir"

    # Proof rather than assumption. `fc-match` resolves through the same
    # fontconfig cache the compositor will use, so if this does not answer
    # Caudex then the bar is about to render in a fallback.
    if command -v fc-match >/dev/null 2>&1; then
        local match
        match="$(fc-match -f '%{family}' Caudex 2>/dev/null)"
        case "$match" in
            Caudex*) hyprx_ui_success "fontconfig resolves Caudex" ;;
            *)
                hyprx_ui_warn "fc-match resolves '$match' for Caudex - it may not be usable yet."
                hyprx_ui_info "Log out and back in, then re-run: hyprx doctor --only fonts"
                ;;
        esac
    fi

    return 0
}

# Used by doctor. Reads the installed fonts, never the network.
hyprx_fonts_status() {
    local dir="$HYPRX_FONT_DIR"

    HYPRX_FONT_MISSING=()
    HYPRX_FONT_BAD=()

    local entry name want have
    for entry in "${HYPRX_FONT_FILES[@]}"; do
        name="${entry%%|*}"
        want="${entry##*|}"

        if [[ ! -f "$dir/$name" ]]; then
            HYPRX_FONT_MISSING+=("$name")
            continue
        fi

        have="$(hyprx_fonts_sha256 "$dir/$name")"
        if [[ -n "$have" && "$have" != "$want" ]]; then
            HYPRX_FONT_BAD+=("$name")
        fi
    done
}
