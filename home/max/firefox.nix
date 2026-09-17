# Firefox, with the 1Password extension preinstalled.
#
# The browser is where most logins actually happen — Google, Claude, Spotify
# all start as a web sign-in — so this is the front half of the credential
# story; ../../modules/desktop/onepassword.nix is the back half.
#
# Enterprise policies are the declarative route to a preinstalled extension.
# Home Manager writes `policies` into the Firefox wrapper's policies.json, so
# a fresh profile already has 1Password and there is no "install the
# extension" step after a disk reset. The extension itself still has to be
# connected to the desktop app on first use, which is a click in its popup.
#
# The extension's ID is its AMO GUID, and the install_url is AMO's stable
# "latest" endpoint for the slug — Firefox fetches the current version from
# there, so nothing here pins an extension version.
#
# Nothing about the profile is managed here on purpose: bookmarks, sessions
# and logins are state, and state lives on the guest disk, not in the repo.
{ ... }:
{
  programs.firefox = {
    enable = true;

    policies = {
      ExtensionSettings = {
        "{d634138d-c276-4fc8-924b-40a0ea21d284}" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi";
        };
      };

      # Firefox's own password manager would compete with 1Password for every
      # login form. Off, so there is exactly one place credentials live.
      PasswordManagerEnabled = false;
      OfferToSaveLogins = false;
    };
  };

  # Make it the default browser, so `xdg-open` and every "log in with
  # browser" flow (Claude Code's OAuth, Spotify's login) land here rather than
  # in whatever the portal picks first.
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
    };
  };
}
