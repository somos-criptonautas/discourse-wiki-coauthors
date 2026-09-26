# Wiki Co-authors

Credits everyone who edited a wiki post, listed under the post itself:

> Co-edited by first_editor, second_editor

Built because Discourse records every wiki edit in `post_revisions` but never
surfaces the contributors as a list — [a feature request open since
2015](https://meta.discourse.org/t/list-of-wiki-editors/26364). Shared Drafts
is not an alternative: publishing a shared draft **deletes the first post's
edit history** and keeps the original creator as the sole author.

## Install

Admin → Customize → Themes → Install → From a git repository, using this
repository's clone URL. Then add the component to the themes that should show
it.

Nothing else needs configuring. The edit history of a **wiki** post is public
regardless of the `edit_history_visible_to_public` site setting — core's
`can_view_edit_history?` returns true whenever `post.wiki` is set — so this
component works for anonymous visitors without loosening edit history
site-wide.

## Settings

| Setting | Default | Notes |
| --- | --- | --- |
| `target_categories` | — | Categories whose wiki posts show the list. Empty means every category. |
| `label` | — | Text shown before the names. Empty uses the viewer's own language. |
| `excluded_users` | — | Usernames never credited. See *Removing someone* below. |
| `label_overrides` | — | Per-category wording. Categories not listed use `label`. |
| `max_avatars` | `5` | Avatars shown before the rest go behind a `+N more` disclosure. |

Ships with English and Spanish translations (`locales/en.yml`, `locales/es.yml`),
covering both the setting descriptions and the default label
(`Co-edited by` / `Coeditado por`). Setting `label` pins one fixed string for
every language.

## Behavior

- Renders only on the **first post** of a topic, only when that post is a
  wiki, only when it has at least one visible revision, and only in the
  target categories.
- Reads `/posts/{id}/revisions/latest.json` for the revision range, then
  fetches each revision in that range in parallel. Revisions hidden by staff
  leave gaps that 404; those are dropped.
- Lists each editor once as an avatar linking to their profile, **ranked by
  how many revisions they made**, most first. People tied on edit count keep
  the order they first edited in. Each avatar's `title` carries the username
  and that edit count; the `alt` carries the username.
- Past `max_avatars`, the remainder goes behind a native `<details>`
  disclosure labelled `+N more`. No JavaScript state, no modal — clicking it
  reveals the rest in place.
- The post's own author is excluded — nobody co-authors their own post.
- Renders plain `<img>` and links rather than reusing core's user components,
  which change between Discourse versions. Avatar URLs come from core's
  `avatarUrl`, so CDN and retina sizing are handled.
- While loading, and on failure, and when there are no co-authors, renders
  nothing at all. No spinner, no error block — it sits above the replies and
  would otherwise push them around for nothing.

### Per-category wording

`label_overrides` pairs a set of categories with the text to use there, so one
category can read *Co-authored by* while the rest read *Co-edited by*. It is an
`objects` setting, so the admin UI gives a category picker and a text field —
add a row per wording, not per category. Categories in no row fall back to
`label`, and `label` itself falls back to the viewer's language. A category
listed in two rows takes the last one.

Text set this way is one fixed string for every language. To vary the wording
*and* keep it translated, leave these settings empty and override
`coauthors.label` per locale in the theme's translation editor instead.

### Removing someone

`excluded_users` drops a username from the list. Be clear about what it is: a
**display filter**, not a removal. The revisions stay in the database and stay
visible to anyone who opens the post's own edit-history modal.

Core offers no surgical removal either. Staff can hide individual revisions,
which drops them for regular users — but `can_view_hidden_post_revisions?` is
`is_staff?`, so **staff still see a hidden editor credited** on the same page.
The admin "permanently delete revisions" action calls `post.revisions
.destroy_all`, so it erases every revision on the post rather than one
person's. Anonymizing a user is the one path that genuinely removes the name,
and Discourse handles it everywhere at once.

### Known limits

- One request per revision, each computing a server-side diff that is thrown
  away. Capped at 50 revisions. A post with dozens of edits makes dozens of
  requests; if that becomes normal on your site, the aggregation belongs in a
  plugin that caches contributor ids in a post custom field on revision
  create.
- Any revision counts as co-authorship, including one that only changed the
  title, tags or category.
- Only the first post is credited. Wiki replies are ignored.
- `version` is `public_version` for non-staff, so a post whose only revisions
  are hidden reads as unedited and renders nothing for regular users.

## Companion: the recognition query

For a leaderboard rather than a per-post credit, run this in Data Explorer:

```sql
-- co-editors in a category, by number of revisions
SELECT pr.user_id, COUNT(*) AS edits, COUNT(DISTINCT p.topic_id) AS topics,
       MAX(pr.created_at) AS last_edit
FROM post_revisions pr
JOIN posts p  ON p.id = pr.post_id
JOIN topics t ON t.id = p.topic_id
WHERE t.category_id = :category_id
  AND p.deleted_at IS NULL AND t.deleted_at IS NULL
  AND pr.user_id <> p.user_id
GROUP BY pr.user_id
ORDER BY edits DESC
```

## Development

```bash
pnpm install
pnpm lint
```

System tests run against a real Discourse via the
[discourse_theme CLI](https://github.com/discourse/discourse_theme):

```bash
discourse_theme rspec .
```

`spec/system/core_features_spec.rb` checks that core features still work with
the component installed; `spec/system/wiki_coauthors_spec.rb` covers the
gating, the de-duplication and ordering, the author exclusion, and that an
anonymous visitor sees the list with `edit_history_visible_to_public` off.
