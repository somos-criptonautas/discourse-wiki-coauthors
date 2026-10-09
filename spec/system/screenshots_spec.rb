# frozen_string_literal: true

# README screenshots. Run by the "Screenshots" workflow, which commits the PNGs
# to docs/screenshots/. Skipped in regular CI.
RSpec.describe "Screenshots" do
  before { skip "set SCREENSHOTS=1 to take screenshots" unless ENV["SCREENSHOTS"] }

  let!(:component) { upload_theme_or_component }

  fab!(:author) { Fabricate(:user, username: "satoshi") }
  fab!(:editors) do
    %w[hal_finney nick_szabo adam_back wei_dai len_sassaman zooko].map do |name|
      Fabricate(:user, username: name)
    end
  end
  fab!(:category) { Fabricate(:category, name: "Wiki") }

  def save(name)
    path = Rails.root.join("tmp/capybara/screenshots/#{name}.png")
    FileUtils.mkdir_p(path.dirname)
    page.save_screenshot(path.to_s)
  end

  it "shows the co-editors under a wiki post" do
    topic = Fabricate(:topic, category: category, title: "Running your own Bitcoin node")
    post = Fabricate(:post, topic: topic, user: author, raw: <<~MD)
      A full node checks every block and transaction against the consensus rules,
      so you don't have to trust anyone else's copy of the chain.

      ## What you need

      - 1 TB of storage, or about 10 GB with pruning
      - A stable connection
      - Bitcoin Core, or a packaged node such as Start9 or Umbrel
    MD
    post.update!(wiki: true)
    editors.each_with_index do |editor, i|
      (editors.size - i).times do |n|
        post.revise(editor, { raw: "#{post.raw}\n<!-- #{i}.#{n} -->" }, force_new_version: true)
      end
    end

    resize_window(width: 1100, height: 760) do
      visit "/t/#{topic.slug}/#{topic.id}"
      expect(page).to have_css(".wiki-coauthors__avatar", count: 5)
      save("coauthors")
    end
  end
end
