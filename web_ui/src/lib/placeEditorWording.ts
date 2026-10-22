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
}

export interface AncestorLore {
  name: string;
  entryCount: number;
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
    };
  }
  const inherited = ancestors.reduce((n, a) => n + a.entryCount, 0);
  return {
    title: isCreate ? `Add a place to ${parentName}` : 'Edit place',
    subtitle: isCreate
      ? `It shares ${parentName}'s lore and climate unless you change it below.`
      : null,
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
  };
}
