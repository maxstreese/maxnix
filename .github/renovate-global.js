// Self-hosted Renovate: the settings only the bot's operator may set.
//
// Read by .github/workflows/renovate.yml. Everything a repository decides for
// itself — what to update, when, how — is in ../renovate.jsonc; this file
// holds what Renovate refuses to take from a repository, because a
// repository could otherwise grant itself the power to run any command.
module.exports = {
  platform: "github",
  repositories: ["maxstreese/maxnix"],

  // renovate.jsonc already exists; there is nothing to onboard, and without
  // a config file Renovate should do nothing rather than guess.
  onboarding: false,
  requireConfig: "required",

  // Taking over from Mend's hosted app. Its open branches and PRs carry
  // commits by renovate[bot]; without these two this Renovate would treat
  // them as edited by someone else and leave them alone. Listed, it adopts
  // them. Drop both once no PR by renovate[bot] is left open.
  gitIgnoredAuthors: ["29139614+renovate[bot]@users.noreply.github.com"],
  ignorePrAuthor: true,

  // The postUpgradeTasks in renovate.jsonc, exactly and nothing else. These
  // are regexes; the anchors make each one match the whole command, so
  // nothing can be appended to an allowed one.
  allowedCommands: [
    "^nix --extra-experimental-features nix-command --extra-experimental-features flakes flake lock$",
    "^scripts/renovate-pypi-rehash$",
  ],
};
