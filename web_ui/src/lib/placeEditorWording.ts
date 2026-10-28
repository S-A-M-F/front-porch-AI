// Copy for the place editor. A draft with a parent is a place inside that
// world, so the editor names the parent; desktop's twin is
// lib/ui/pages/world_management/world_dialog_wording.dart.
export interface PlaceEditorWording {
  title: string;
  subtitle: string | null;
  nameLabel: string;
  descriptionLabel: string;
  descriptionHint: string;
  saveLabel: string;
  loreTitle: string;
  loreEmptyText: string;
  /** Lore the parent chain brings into this place's chats; null if none. */
  inheritedLoreLine: string | null;
  /** Set when the top-level world above this place has weather off. */
  weatherOff: WeatherOffWording | null;
}

export interface WeatherOffWording {
  title: string;
  body: (ownsClimate: boolean) => string;
  inheritBody: string;
  ownTag: (ownsClimate: boolean) => string;
}

export interface AncestorLore {
  name: string;
  /** Switched-on entries only. */
  entryCount: number;
  /** False when this world's weather switch is off. */
  climateEnabled?: boolean;
}

/** The top-level world's climate switch: off reaches every place in it. */
export const CLIMATE_SWITCH_HINT =
  'Off = no weather, atmosphere or gravity anywhere in this world, including the places inside it.';

/** The note under a weather-off world's switch; null when no place inside owns a climate. */
export function pausedPlacesNote(names: string[]): { title: string; body: string } | null {
  const n = names.length;
  if (n === 0) return null;
  const list =
    n <= 3
      ? n === 1
        ? names[0]
        : `${names.slice(0, -1).join(', ')} and ${names[n - 1]}`
      : `${names.slice(0, 2).join(', ')} and ${n - 2} more`;
  return {
    title: n === 1 ? '1 place inside sets its own climate' : `${n} places inside set their own climate`,
    body:
      n === 1
        ? `${list} keeps its climate, but it's paused while this is off. Turn it back on and it comes back as before.`
        : `${list} keep their climates, but they're paused while this is off. Turn it back on and they come back as before.`,
  };
}

function weatherOffWording(root: string): WeatherOffWording {
  return {
    title: `Weather is off for ${root}`,
    body: (own) =>
      own
        ? `This place's climate is saved but paused: it has no effect in chats until ${root}'s weather is turned on in its editor.`
        : `Nothing inside it has weather, atmosphere or gravity. A climate set here won't do anything until ${root}'s weather is turned on in its editor.`,
    inheritBody: `No weather: ${root} has weather off.`,
    ownTag: (own) =>
      own ? `Paused while ${root}'s weather is off` : `No effect while ${root}'s weather is off`,
  };
}

// [ancestors] is the parent chain nearest-first; empty = a top-level world.
export function placeEditorWording(
  isCreate: boolean,
  ancestors: AncestorLore[],
): PlaceEditorWording {
  const parentName = ancestors[0]?.name ?? null;
  if (parentName == null) {
    return {
      title: isCreate ? 'New place' : 'Edit place',
      subtitle: null,
      nameLabel: 'Name',
      descriptionLabel: 'Description (place prose)',
      descriptionHint:
        'What it feels like to be here — can reach the story when inject is on',
      saveLabel: 'Save place',
      loreTitle: 'Lorebook entries',
      loreEmptyText: 'No entries. Lore is injected when its keywords appear in the chat.',
      inheritedLoreLine: null,
      weatherOff: null,
    };
  }
  const root = ancestors[ancestors.length - 1];
  const offRoot = root.climateEnabled === false ? root.name : null;
  const inherited = ancestors.reduce((n, a) => n + a.entryCount, 0);
  return {
    title: isCreate ? `Add a place to ${parentName}` : 'Edit place',
    subtitle: !isCreate
      ? null
      : offRoot
        ? `It shares ${parentName}'s lore. ${offRoot} has weather off, so this place has none either.`
        : `It shares ${parentName}'s lore and climate unless you change it below.`,
    nameLabel: 'Place name',
    descriptionLabel: 'Description',
    descriptionHint:
      'What it feels like to stand here — can reach the story when inject is on',
    saveLabel: isCreate ? 'Add place' : 'Save place',
    loreTitle: "This place's lore",
    loreEmptyText:
      'No entries for this place yet. Add lore that only matters here, like who runs it or what the locals fear.',
    inheritedLoreLine:
      inherited === 0
        ? null
        : `Also active here: ${inherited} lore ${inherited === 1 ? 'entry' : 'entries'} from ${ancestors
            .map((a) => a.name)
            .join(' and ')}. When both books have an entry in the same group, this place's entry wins.`,
    weatherOff: offRoot ? weatherOffWording(offRoot) : null,
  };
}
