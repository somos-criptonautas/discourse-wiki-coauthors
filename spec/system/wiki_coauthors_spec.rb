# frozen_string_literal: true

RSpec.describe "Wiki co-authors" do
  let!(:component) { upload_theme_or_component }

  fab!(:author) { Fabricate(:user, username: "original_author") }
  fab!(:first_editor) { Fabricate(:user, username: "first_editor") }
  fab!(:second_editor) { Fabricate(:user, username: "second_editor") }

  fab!(:target_category) { Fabricate(:category, name: "Docs") }
  fab!(:other_category) { Fabricate(:category, name: "Guides") }

  before do
    component.update_setting(:target_categories, target_category.id.to_s)
    component.save!
  end

  # A wiki post with one revision per editor, in the order given. Revisions are
  # what the component reads; a plain `post.update` would not create any.
  def wiki_post_in(category, editors: [], wiki: true)
    post = Fabricate(:post, user: author, topic: Fabricate(:topic, category: category))
    post.update!(wiki: wiki)

    editors.each_with_index do |editor, index|
      post.revise(editor, { raw: "#{post.raw} — edit #{index}" }, force_new_version: true)
    end

    post
  end

  def visit_post(post)
    visit "/t/#{post.topic.slug}/#{post.topic.id}"
  end

  def listed_coauthors
    page.all(".wiki-coauthors__user").map(&:text)
  end

  it "lists each editor once, in the order they first edited" do
    post = wiki_post_in(target_category, editors: [second_editor, first_editor, second_editor])

    visit_post(post)

    expect(page).to have_css(".wiki-coauthors")
    expect(listed_coauthors).to eq(%w[second_editor first_editor])
  end

  it "excludes the post's own author" do
    post = wiki_post_in(target_category, editors: [author, first_editor])

    visit_post(post)

    expect(page).to have_css(".wiki-coauthors")
    expect(listed_coauthors).to eq(%w[first_editor])
  end

  it "renders nothing on an unedited wiki post" do
    post = wiki_post_in(target_category)

    visit_post(post)

    expect(page).to have_css(".cooked")
    expect(page).to have_no_css(".wiki-coauthors")
  end

  it "renders nothing on a non-wiki post, edited or not" do
    post = wiki_post_in(target_category, editors: [first_editor], wiki: false)

    visit_post(post)

    expect(page).to have_css(".cooked")
    expect(page).to have_no_css(".wiki-coauthors")
  end

  it "renders nothing outside the target categories" do
    post = wiki_post_in(other_category, editors: [first_editor])

    visit_post(post)

    expect(page).to have_css(".cooked")
    expect(page).to have_no_css(".wiki-coauthors")
  end

  it "renders in every category when no target category is set" do
    component.update_setting(:target_categories, "")
    component.save!
    post = wiki_post_in(other_category, editors: [first_editor])

    visit_post(post)

    expect(page).to have_css(".wiki-coauthors")
    expect(listed_coauthors).to eq(%w[first_editor])
  end

  it "credits anonymous visitors too, without the public edit history setting" do
    SiteSetting.edit_history_visible_to_public = false
    post = wiki_post_in(target_category, editors: [first_editor])

    visit_post(post)

    expect(page).to have_css(".wiki-coauthors")
    expect(listed_coauthors).to eq(%w[first_editor])
  end
end
