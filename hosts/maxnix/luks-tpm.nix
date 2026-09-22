# Let the TPM unlock the root, once something has been enrolled into it.
#
# A plain attrset rather than a module function, so it can be used twice: as
# an import in ./disk.nix, and as makeDiskoTest's `extraSystemConfig` in
# ../../tests/disk.nix. That sharing is the whole reason this is its own file.
#
# The first attempt at this put the option in disk.nix and claimed the disk
# test covered it. It did not: makeDiskoTest builds its installed system from
# the layout attrset plus its own defaults, and never imports disk.nix, so the
# option changed nothing there — the two derivation hashes were identical
# before and after adding it. Shared this way, the test's system carries the
# same line the real machine does.
#
# What is being tested is the *fallback*, and it is the part that matters:
# with no TPM and nothing enrolled, systemd-cryptsetup must fall through to
# asking for the passphrase. checks.metal-boots is exactly that situation — a
# VM with no TPM — so a regression that made this a hard requirement would
# hang the test rather than brick a laptop.
#
# Enrolment itself is one command on the real machine, run after Secure Boot
# is on, since the TPM should only release the key to a boot chain it has
# measured:
#
#   sudo systemd-cryptenroll --tpm2-device=auto \
#     --tpm2-pcrs=0+2+7 /dev/disk/by-partlabel/disk-main-luks
#
# crypttabExtraOpts needs systemd in the initrd, which this config has.
{
  boot.initrd.luks.devices.crypted.crypttabExtraOpts = [ "tpm2-device=auto" ];
}
