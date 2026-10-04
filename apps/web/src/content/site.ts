/**
 * Every string, path, and metadata color the website shows, in one place.
 * Controls copy mirrors the game's AppCopy
 * (game/src/application/app/app_copy.gd); keep the two in sync.
 *
 * @see ../../../../docs/concepts/web.md
 * @see ../../../../docs/concepts/ux.md
 */

export const SiteName = "Riposte";

/** Must match `globals.css` tokens, `favicon.svg`, and `site.webmanifest`. */
export const SiteTheme = {
  background: "#ffffff",
  themeColor: "#404548",
} as const;

export const SitePath = {
  home: "/",
  play: "/play",
  howToPlay: "/how-to-play",
  about: "/about",
} as const;

export const SiteCopy = {
  description:
    "Riposte is a physics-driven sword duel for the browser: two verbs, real steel, and the timing between them.",
  tagline: "Steel, timing, and the space between.",
  homeLead:
    "Move and attack. Momentum, blade contact, and timing decide every exchange. Duel the CPU at three difficulties or learn in Training.",
  playCta: "Play Riposte",
  play: "Play",
  home: "Home",
  howToPlay: "How to Play",
  about: "About",
  primaryNav: "Primary",
  skipToContent: "Skip to content",
  community: "Community",
  discord: "Discord",
  patreon: "Patreon",
  comingSoon: "Coming soon",
  opensInNewTab: "(opens in a new tab)",
  playCheckingTitle: "Finding your duel",
  playCheckingBody: "Checking where Riposte runs for this site.",
  playOpeningTitle: "Opening Riposte",
  playOpeningBody:
    "Taking you to the game. If nothing happens, use the button below.",
  playOpeningCta: "Open the game",
  playUnpublishedTitle: "Riposte is not published yet",
  playUnpublishedBody:
    "The public game will live on itch.io. Until it is published, run it locally: Play on localhost opens the Godot Web export at http://127.0.0.1:8060/.",
  howToPlayLead: "Two verbs. That is the whole game.",
  controlsMove: "Move",
  controlsMoveHow: "WASD or arrow keys · Left thumb on touch screens",
  controlsAttack: "Attack",
  controlsAttackHow:
    "Left mouse or Space · Right side of the screen on touch screens",
  controlsVerbs:
    "Tap for a quick cut. Hold to wind back and charge. Release to swing.",
  controlsPhysics:
    "Your sword stays where it stops; the next cut starts there. Put your blade in their path to parry, then strike before they recover.",
  controlsPause: "Esc pauses. You always face your opponent.",
  controlsTraining:
    "New to Riposte? Start Training from the game's How to Play screen. Every lesson is learned by doing.",
  aboutLead:
    "A one-on-one duel where every outcome comes from simulated steel.",
  aboutBody:
    "Riposte simulates each fighter's footwork and sword as physical bodies: where a blade travels, what it meets, and how hard it lands decide the exchange, not canned animations. This release is single player: Quick Play against a CPU at three difficulties, plus Training.",
  aboutPlatform:
    "The game is one Godot application that runs in your browser on desktop and mobile. This site is its front door.",
  notFoundTitle: "Page not found",
  notFoundBody: "That page does not exist. Return home to continue.",
  errorTitle: "Something went wrong",
  errorBody: "An unexpected error occurred. Try again, or return home.",
  tryAgain: "Try again",
  backHome: "Back to home",
} as const;
