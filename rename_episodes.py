#!/usr/bin/env python3
"""
Rename TV episode files to: ShowName.SxxExx.EpisodeTitle.ext
Run without arguments for dry-run. Pass --execute to actually rename.
Pass --show-skipped to also print files that can't be auto-renamed.
"""
import os
import re
import sys

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
VIDEO_EXTS = {'.mkv', '.mp4', '.avi'}

# Episode code patterns — groups numbered in order of alternation:
#  1,2 → S01E01 / S01_E01 / S01-E01
#  3,4 → 1x01  (NxNN)
#  5,6 → Season 2 Episode 10
#  7   → EP01  (implied season 1)
#  8   → Episode 01 (implied season 1)
EP_PATTERN = re.compile(
    r'(?:'
    r'[Ss](\d{1,2})[\s._-]?[Ee](\d{1,2})'                              # S01E01 / S01_E01
    r'|(\d{1,2})[xX](\d{1,2})'                                          # 1x01
    r'|[Ss]eason[\s._-]?(\d+)[\s._-]?[Ee]pisode[\s._-]?(\d{1,2})'     # Season 2 Episode 10
    r'|(?<![A-Za-z])EP(\d{1,2})(?![A-Za-z])'                           # EP01  (Planet Earth)
    r'|(?<![A-Za-z])Episode[\s._-]?(\d{1,2})(?!\d)'                    # Episode 01 (The Pacific)
    r')'
)

TECH_SET = {
    # Resolutions (also caught by RESOLUTION_RE)
    '480p', '576p', '720p', '1080p', '2160p', '4k',
    # Sources
    'bluray', 'bdrip', 'brrip', 'hddvd', 'bdmux',
    'webdl', 'webrip', 'webmux', 'dlmux', 'nfrip',
    'dvdrip', 'dvdscr', 'dvd', 'hdtv', 'pdtv', 'sdtv',
    # Streaming services / piracy labels
    'amzn', 'dsnp', 'hmax', 'pcok', 'primewire',
    # Video codecs
    'x264', 'x265', 'h264', 'h265', 'hevc', 'avc', 'av1', 'xvid', 'divx',
    # Audio
    'ac3', 'aac', 'flac', 'dts', 'eac3', 'atmos', 'truehd', 'opus',
    '6ch', 'dd5', 'mp3',
    # Bit depth / HDR
    '10bit', '8bit', 'hdr', 'sdr', 'dovi', 'hdr10',
    # Language codes (common in multi-audio releases)
    'ita', 'eng', 'multi', 'dubbed', 'sub', 'subs',
    # Release modifiers
    'repack', 'proper', 'remux',
    # Encoding metrics / tools
    'ssim',
}

RESOLUTION_RE   = re.compile(r'^\d{3,4}[pP]$')
CHECKSUM_RE     = re.compile(r'^[0-9a-fA-F]{7,9}$')
CHANNELS_RE     = re.compile(r'^\d\.\d$')           # 5.1 / 2.0 / 7.1
YEAR_RE         = re.compile(r'^(?:19|20)\d{2}$')   # standalone release year
ENCODER_TAG_RE  = re.compile(r'^[a-zA-Z]{2,5}\d{2,4}$')  # jpv711, FS85
# Detects a secondary episode code in title position (multi-episode files):
# matches things like  3x18  e24  E18
SECONDARY_EP_RE = re.compile(r'^(?:[Ss]?\d{1,2}[xX]|[eE])\d{1,2}$')


def normalize_compound_tokens(s):
    """Collapse hyphenated tech tokens before splitting so they stay as one token."""
    s = re.sub(r'(?i)\bweb[-.]dl\b',    'WEBDL',  s)
    s = re.sub(r'(?i)\bweb[-.]rip\b',   'WEBRIP', s)
    s = re.sub(r'(?i)\bblu[-.]ray\b',   'BLURAY', s)
    s = re.sub(r'(?i)\b10[-.]bit\b',    '10bit',  s)
    s = re.sub(r'(?i)\bh[.]26([45])\b', r'H26\1', s)
    return s


def is_tech(token):
    t = token.lower().strip('._-')
    if not t:
        return False
    if t in TECH_SET:
        return True
    if RESOLUTION_RE.match(token):
        return True
    if CHECKSUM_RE.match(token):
        return True
    if CHANNELS_RE.match(token):
        return True
    if YEAR_RE.match(token):
        return True
    return False


def is_encoder_tag(token):
    """Trailing uploader/encoder tags like jpv711 that aren't real title words."""
    return bool(ENCODER_TAG_RE.match(token))


SEASON_WORD_RE = re.compile(r'^(?:season|complete|series|vol|volume)$', re.IGNORECASE)
DIR_SEASON_RE  = re.compile(r'^[Ss]\d{2}')  # S01, S01-S07, etc.


def clean_dir_show_name(dirname):
    """Strip tech/release junk from a directory name to get just the show name."""
    s = normalize_compound_tokens(dirname)
    tokens = re.split(r'[_.\-\s]+', s)
    name_tokens = []
    for tok in tokens:
        tok = tok.strip()
        if not tok:
            continue
        if is_tech(tok):
            break
        if SEASON_WORD_RE.match(tok):
            break
        if DIR_SEASON_RE.match(tok):
            break
        name_tokens.append(tok)
    if name_tokens:
        return '.'.join(name_tokens)
    return re.sub(r'[_\-\s]+', '.', dirname).strip('.')


def build_new_name(dirpath, filename):
    stem, ext = os.path.splitext(filename)
    if ext.lower() not in VIDEO_EXTS:
        return None, "not a video file"

    m = EP_PATTERN.search(stem)
    if not m:
        return None, "no episode code found"

    # Prefer the filename prefix (before episode code) as show name — it's
    # already clean. Fall back to stripping tech tags from the directory name.
    prefix = stem[:m.start()].strip('._- ')
    if prefix:
        show_name = re.sub(r'[_\-\s]+', '.', prefix).strip('.')
    else:
        show_name = clean_dir_show_name(os.path.basename(dirpath))

    g = m.groups()
    if g[0] is not None:       # S01E01 form
        season, episode = g[0], g[1]
    elif g[2] is not None:     # NxNN form
        season, episode = g[2], g[3]
    elif g[4] is not None:     # Season N Episode N form
        season, episode = g[4], g[5]
    elif g[6] is not None:     # EP01 form (Planet Earth etc.)
        season, episode = '1', g[6]
    else:                      # Episode N form (The Pacific etc.)
        season, episode = '1', g[7]
    ep_code = f"S{int(season):02d}E{int(episode):02d}"

    after = stem[m.end():]

    # Detect split-file suffix before discarding tech info
    part_match = re.search(r'[._]part(\d+)$', after, re.IGNORECASE)
    part_suffix = f".part{part_match.group(1)}" if part_match else ""

    after = re.sub(r'^[._\-\s,]+', '', after)
    after = normalize_compound_tokens(after)

    tokens = re.split(r'[._\-\s,]+', after)
    title_tokens = []
    for tok in tokens:
        tok = tok.strip()
        if not tok:
            continue
        if is_tech(tok):
            break
        if SECONDARY_EP_RE.match(tok):  # extra episode code in multi-ep files
            continue
        title_tokens.append(tok)

    while title_tokens and is_encoder_tag(title_tokens[-1]):
        title_tokens.pop()

    title = '.'.join(title_tokens)

    base = f"{show_name}.{ep_code}.{title}" if title else f"{show_name}.{ep_code}"
    return base + part_suffix + ext.lower(), None


def main():
    dry_run      = '--execute' not in sys.argv
    show_skipped = '--show-skipped' in sys.argv

    if dry_run:
        print("DRY RUN — no files will be changed. Pass --execute to rename.\n")

    total = renamed = skipped = collisions = 0
    seen_targets = {}

    for dirpath, dirnames, filenames in os.walk(BASE_DIR):
        dirnames.sort()
        for filename in sorted(filenames):
            _, ext = os.path.splitext(filename)
            if ext.lower() not in VIDEO_EXTS:
                continue
            total += 1

            new_name, err = build_new_name(dirpath, filename)
            if err:
                skipped += 1
                if show_skipped:
                    rel = os.path.relpath(os.path.join(dirpath, filename), BASE_DIR)
                    print(f"SKIP  {rel}  ({err})")
                continue

            if new_name == filename:
                continue

            old_path = os.path.join(dirpath, filename)
            new_path = os.path.join(dirpath, new_name)

            if new_path in seen_targets:
                collisions += 1
                rel = os.path.relpath(dirpath, BASE_DIR)
                print(f"COLLISION [{rel}]")
                print(f"  {filename!r} → {new_name!r}")
                print(f"  already claimed by {seen_targets[new_path]!r}")
                print(f"  One of these is likely a duplicate — delete it manually.")
                print()
                continue
            seen_targets[new_path] = filename

            rel_dir = os.path.relpath(dirpath, BASE_DIR)
            print(f"  [{rel_dir}]")
            print(f"  OLD: {filename}")
            print(f"  NEW: {new_name}")
            print()
            renamed += 1

            if not dry_run:
                if os.path.exists(new_path):
                    print(f"  ERROR: target already exists on disk — skipping.")
                    collisions += 1
                else:
                    os.rename(old_path, new_path)

    action = "Would rename" if dry_run else "Renamed"
    print("─" * 60)
    print(f"Total video files   : {total}")
    print(f"{action}          : {renamed}")
    print(f"Skipped (no ep code): {skipped}")
    if collisions:
        print(f"Collisions          : {collisions}  ← review manually")


if __name__ == '__main__':
    main()
