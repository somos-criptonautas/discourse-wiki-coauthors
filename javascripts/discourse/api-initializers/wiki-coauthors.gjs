import Component from "@glimmer/component";
import { apiInitializer } from "discourse/lib/api";
import getURL from "discourse/lib/get-url";
import Post from "discourse/models/post";
import { i18n } from "discourse-i18n";
import DAsyncContent from "discourse/ui-kit/d-async-content";

// Core's revision serializer only ever reports the last 99 revisions, so stay
// under that and keep the request burst bounded however edited a post is.
//
// ponytail: one request per revision, each one computing a server-side diff we
// throw away. Fine for the handful of edits a co-authored wiki post collects.
// If posts get heavily edited, move the aggregation into a plugin that caches
// contributor ids in a post custom field when a revision is created.
const MAX_REVISIONS = 50;

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

  // Seeded with the post's own author: nobody is a co-author of their own
  // post. `username` is already lowercased by the serializer.
  const seen = new Set([(post.username || "").toLowerCase()]);

  return revisions
    .filter((revision) => {
      if (seen.has(revision.username)) {
        return false;
      }
      seen.add(revision.username);
      return true;
    })
    .map((revision) => ({
      username: revision.username,
      displayUsername: revision.display_username,
      url: getURL(`/u/${revision.username}`),
    }));
}

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
            {{#each editors key="username" as |editor|}}
              <li class="wiki-coauthors__item">
                <a class="wiki-coauthors__user" href={{editor.url}}>
                  {{editor.displayUsername}}
                </a>
              </li>
            {{/each}}
          </ul>
        </div>
      </:content>
    </DAsyncContent>
  </template>
}

export default apiInitializer((api) => {
  const categoryIds = parseIds(settings.target_categories);

  // `version` is `public_version` for everyone but staff, so a post whose only
  // revisions are hidden reads as unedited and renders nothing.
  const shouldRender = (post) =>
    post?.firstPost &&
    post.wiki &&
    post.version > 1 &&
    (categoryIds.length === 0 || categoryIds.includes(post.topic?.category_id));

  // An empty setting falls back to the theme's own translation, so a
  // Spanish-reading member sees "Coeditado por" without anyone configuring it.
  const label = settings.label || i18n(themePrefix("coauthors.label"));

  const Connector = <template>
    {{#if (shouldRender @outletArgs.post)}}
      <WikiCoauthors @post={{@outletArgs.post}} @label={{label}} />
    {{/if}}
  </template>;

  api.renderAfterWrapperOutlet("post-content-cooked-html", Connector);
});
