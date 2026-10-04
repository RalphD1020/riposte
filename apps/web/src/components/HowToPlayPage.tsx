/**
 * How to Play: the two verbs on every device and the physical rules that
 * make them deep. Mirrors the in-game How to Play screen.
 *
 * @see ../../../../docs/concepts/controls.md
 * @see ../../../../docs/concepts/web.md
 */

import { PlayCta } from "@/components/PlayCta";
import { SiteCopy } from "@/content/site";

export function HowToPlayPage() {
  return (
    <div className="page">
      <h1 className="page__title">{SiteCopy.howToPlay}</h1>
      <p className="page__lede">{SiteCopy.howToPlayLead}</p>
      <dl className="controls-list">
        <div className="controls-list__row">
          <dt>{SiteCopy.controlsMove}</dt>
          <dd>{SiteCopy.controlsMoveHow}</dd>
        </div>
        <div className="controls-list__row">
          <dt>{SiteCopy.controlsAttack}</dt>
          <dd>{SiteCopy.controlsAttackHow}</dd>
        </div>
      </dl>
      <p className="page__body">{SiteCopy.controlsVerbs}</p>
      <p className="page__body">{SiteCopy.controlsPhysics}</p>
      <p className="page__body">{SiteCopy.controlsPause}</p>
      <p className="page__body">{SiteCopy.controlsTraining}</p>
      <PlayCta />
    </div>
  );
}
