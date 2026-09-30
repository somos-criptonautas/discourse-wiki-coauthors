import Component from "@glimmer/component";
import { apiInitializer } from "discourse/lib/api";
import { avatarUrl } from "discourse/lib/avatar-utils";
import Post from "discourse/models/post";
import { i18n } from "discourse-i18n";
import DAsyncContent from "discourse/ui-kit/d-async-content";
import DUserLink from "discourse/ui-kit/d-user-link";

// Core's revision serializer only ever reports the last 99 revisions, so stay
// under that and keep the request burst bounded however edited a post is.
//
// ponytail: one request per revision, each one computing a server-side diff we
// throw away. Fine for the handful of edits a co-authored wiki post collects.
// If posts get heavily edited, move the aggregation into a plugin that caches
// contributor ids in a post custom field when a revision is created.
const MAX_REVISIONS = 50;

// A display filter, not a removal: the revisions stay in the database and stay
// visible in the post's own history modal. Serializer usernames are lowercased,
// so match on that.
const excludedUsers = new Set(
  (settings.excluded_users || "")
    .split("|")
    .filter(Boolean)
    .map((username) => username.trim().toLowerCase())
);

// Category id -> label. A category listed in two overrides takes the last one,
// which is how the Map constructor resolves duplicate keys.
const labelOverrides = new Map(
  (settings.label_overrides || []).flatMap((override) =>
    (override.category_ids || []).map((id) => [id, override.label])
  )
);

// Past this many, the rest go behind a disclosure. `<details>` does the
// toggling, so there is no open/closed state to track.
const maxAvatars = Math.max(1, parseInt(settings.max_avatars, 10) || 5);

const parseIds = (value) =>
  (value || "")
    .split("|")
    .filter(Boolean)
    .map((id) => parseInt(id, 10));

// Revision numbers start at 2 and have gaps wherever staff hid a revision.
// Those gaps 404, which `allSettled` drops.
async function fetchEditors(post) {
  const latest = await Post.loadRevision(post.id, "latest");

  const numbers = [];
  for (
    let number = latest.first_revision;
    number < latest.last_revision && numbers.length < MAX_REVISIONS;
    number++
  ) {
    numbers.push(number);
  }

  const settled = await Promise.allSettled(
    numbers.map((number) => Post.loadRevision(post.id, number))
  );

  const revisions = settled
    .filter((result) => result.status === "fulfilled")
    .map((result) => result.value)
    .concat(latest)
    .sort((a, b) => a.current_revision - b.current_revision);

  // Skipped outright: the post's own author (nobody co-authors their own post)
  // and the excluded usernames. `username` is already lowercased by the
  // serializer.
  const skip = new Set([(post.username || "").toLowerCase(), ...excludedUsers]);

  const counts = new Map();

  for (const revision of revisions) {
    if (skip.has(revision.username)) {
      continue;
    }

    const counted = counts.get(revision.username);

    if (counted) {
      counted.edits++;
    } else {
      counts.set(revision.username, {
        username: revision.username,
        displayUsername: revision.display_username,
        avatarTemplate: revision.avatar_template,
        edits: 1,
      });
    }
  }

  // Most edits first. `sort` is stable, and `counts` was filled in revision
  // order, so people tied on edit count keep the order they first edited in.
  return [...counts.values()]
    .sort((a, b) => b.edits - a.edits)
    .map((editor) => ({
      ...editor,
      avatarUrl: avatarUrl(editor.avatarTemplate, "small"),
    }));
}

const visibleEditors = (editors) => editors.slice(0, maxAvatars);
const overflowEditors = (editors) => editors.slice(maxAvatars);
const overflowLabel = (editors) =>
  i18n(themePrefix("coauthors.more"), { count: editors.length - maxAvatars });

// `title` rather than a visible name: the list is avatars, and the edit count
// is the reason this person is ranked where they are.
// DUserLink carries `data-user-card`, which is what core's click handler looks
// for to open the profile card. It also builds the profile href and respects
// `hide_user_profiles_from_public` for anonymous visitors.
const CoauthorAvatar = <template>
  <li class="wiki-coauthors__item">
    <DUserLink
      class="wiki-coauthors__user"
      title="{{@editor.displayUsername}} ({{@editor.edits}})"
      @username={{@editor.username}}
    >
      <img
        class="wiki-coauthors__avatar"
        src={{@editor.avatarUrl}}
        alt={{@editor.displayUsername}}
        width="24"
        height="24"
        loading="lazy"
      />
    </DUserLink>
  </li>
</template>;

class WikiCoauthors extends Component {
  // An arrow field, so the template reads it as a value rather than invoking
  // it as a helper, and so DAsyncContent can re-run it when `@context` changes.
  loadEditors = (post) => fetchEditors(post);

  <template>
    <DAsyncContent @asyncData={{this.loadEditors}} @context={{@post}}>
      {{! Nothing renders until the list is known: no spinner, no error block,
          no empty state. This sits under the post body, and a failed or empty
          lookup is not worth pushing the replies down for. }}
      <:loading></:loading>
      <:empty></:empty>
      <:error></:error>
      <:content as |editors|>
        <div class="wiki-coauthors">
          <span class="wiki-coauthors__label">{{@label}}</span>
          <ul class="wiki-coauthors__list">
            {{#each (visibleEditors editors) key="username" as |editor|}}
              <CoauthorAvatar @editor={{editor}} />
            {{/each}}
          </ul>
          {{#if (overflowEditors editors)}}
            <details class="wiki-coauthors__more">
              <summary class="wiki-coauthors__more-toggle">
                {{overflowLabel editors}}
              </summary>
              <ul class="wiki-coauthors__list">
                {{#each (overflowEditors editors) key="username" as |editor|}}
                  <CoauthorAvatar @editor={{editor}} />
                {{/each}}
              </ul>
            </details>
          {{/if}}
        </div>
      </:content>
    </DAsyncContent>
  </template>
}

export default apiInitializer((api) => {
  const categoryIds = parseIds(settings.target_categories);
  const tags = new Set(
    (settings.target_tags || "")
      .split("|")
      .filter(Boolean)
      .map((tag) => tag.trim().toLowerCase())
  );

  // Category and tag are a union, not an intersection: a topic qualifies by
  // sitting in a listed category OR by carrying a listed tag. With neither set,
  // every wiki post qualifies.
  const inScope = (topic) => {
    if (categoryIds.length === 0 && tags.size === 0) {
      return true;
    }

    if (categoryIds.includes(topic?.category_id)) {
      return true;
    }

    // Core normalizes `topic.tags` to `{ name, id }` objects via `serializeTags`,
    // but plain strings reach here on some paths, so accept both.
    return (topic?.tags || []).some((tag) => {
      const name = typeof tag === "string" ? tag : tag?.name;
      return !!name && tags.has(name.toLowerCase());
    });
  };

  // `version` is `public_version` for everyone but staff, so a post whose only
  // revisions are hidden reads as unedited and renders nothing.
  const shouldRender = (post) =>
    post?.firstPost && post.wiki && post.version > 1 && inScope(post.topic);

  // An empty setting falls back to the theme's own translation, so a
  // Spanish-reading member sees "Coeditado por" without anyone configuring it.
  const defaultLabel = settings.label || i18n(themePrefix("coauthors.label"));

  const labelFor = (post) =>
    labelOverrides.get(post?.topic?.category_id) || defaultLabel;

  const Connector = <template>
    {{#if (shouldRender @outletArgs.post)}}
      <WikiCoauthors
        @post={{@outletArgs.post}}
        @label={{labelFor @outletArgs.post}}
      />
    {{/if}}
  </template>;

  api.renderAfterWrapperOutlet("post-content-cooked-html", Connector);
});
