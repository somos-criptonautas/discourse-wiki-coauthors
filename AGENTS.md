# Wiki Co-authors — agent guide

Rules for anyone changing this repo, people and AI agents alike. Org-wide
conventions (README, licenses, commits) are in the [contributing guide](https://github.com/somos-criptonautas/.github/blob/main/CONTRIBUTING.md).

## Checks

```bash
pnpm install && pnpm lint          # eslint, prettier, stylelint, types
discourse_theme rspec .            # system specs against a real Discourse
```

CI runs both. Screenshots in `docs/screenshots/` come from
`spec/system/screenshots_spec.rb` via Actions → Screenshots; update that spec
when the UI changes.

## Things that are easy to get wrong

- The list is built from `/posts/{id}/revisions/{n}.json`, one request per
  revision, capped by `MAX_REVISIONS`. Anything that adds requests per post
  belongs in a plugin, not here.
- Wiki edit history is public whatever `edit_history_visible_to_public` says,
  which is why anonymous visitors see the list. Keep a spec for it.
- `excluded_users` only hides names; revisions stay visible in the history modal.
  Don't describe it as removal.
- No spinner and no error block: on failure or with no co-authors the component
  renders nothing.
