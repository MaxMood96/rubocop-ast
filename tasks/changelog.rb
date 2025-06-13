# frozen_string_literal: true

# Changelog utility
class Changelog # rubocop:disable Metrics/ClassLength
  ENTRIES_PATH = 'changelog/'
  FIRST_HEADER = /#{Regexp.escape("## master (unreleased)\n")}/m.freeze
  ENTRIES_PATH_TEMPLATE = "#{ENTRIES_PATH}%<type>s_%<name>s.md"
  TYPE_REGEXP = /#{Regexp.escape(ENTRIES_PATH)}([a-z]+)_/.freeze
  TYPE_TO_HEADER = { new: 'New features', fix: 'Bug fixes', change: 'Changes' }.freeze
  HEADER = /### (.*)/.freeze
  PATH = 'CHANGELOG.md'
  REF_URL = 'https://github.com/rubocop/rubocop-ast'
  MAX_LENGTH = 40
  CONTRIBUTOR = '[@%<user>s]: https://github.com/%<user>s'
  SIGNATURE = Regexp.new(format(Regexp.escape("([@%<user>s][])\n"), user: '(\w+)'))

  # New entry
  Entry = Struct.new(:type, :body, :ref_type, :ref_id, :user, keyword_init: true) do
    def initialize(type:, body: last_commit_title, ref_type: :pull, ref_id: nil, user: github_user)
      id, body = extract_id(body)
      ref_id ||= id || 'x'
      super
    end

    def write
      FileUtils.mkdir_p(ENTRIES_PATH)
      File.write(path, content)
      path
    end

    def path
      format(ENTRIES_PATH_TEMPLATE, type: type, name: str_to_filename(body))
    end

    def content
      period = '.' unless body.end_with? '.'
      "* #{ref}: #{body}#{period} ([@#{user}][])\n"
    end

    def ref
      "[##{ref_id}](#{REF_URL}/#{ref_type}/#{ref_id})"
    end

    def last_commit_title
      `git log -1 --pretty=%B`.lines.first.chomp
    end

    def extract_id(body)
      /^\[Fixes #(\d+)\] (.*)/.match(body)&.captures || [nil, body]
    end

    def str_to_filename(str)
      str
        .downcase
        .split
        .each { |s| s.gsub!(/\W/, '') }
        .reject(&:empty?)
        .inject do |result, word|
          s = "#{result}_#{word}"
          return result if s.length > MAX_LENGTH

          s
        end
    end

    def github_user
      user = `git config --global credential.username`.chomp
      if user.empty?
        warn 'Set your username with `git config --global credential.username "myusernamehere"`'
      end

      user
    end
  end

  def self.pending?
    entry_paths.any?
  end

  def self.entry_paths
    Dir["#{ENTRIES_PATH}*"]
  end

  def self.read_entries
    entry_paths.to_h do |path|
      [path, File.read(path)]
    end
  end

  attr_reader :header, :rest

  def initialize(content: File.read(PATH), entries: Changelog.read_entries)
    require 'strscan'

    parse(content)
    @entries = entries
  end

  def and_delete!
    @entries.each_key do |path|
      File.delete(path)
    end
  end

  def merge!
    File.write(PATH, merge_content)
    self
  end

  def unreleased_content
    entry_map = parse_entries(@entries)
    merged_map = merge_entries(entry_map)
    merged_map.flat_map do |header, things|
      [
        "### #{header}\n",
        *things,
        ''
      ]
    end.join("\n")
  end

  def merge_content
    [
      @header,
      unreleased_content,
      @rest,
      *new_contributor_lines
    ].join("\n")
  end

  def new_contributor_lines
    unique_contributor_names = contributors.map { |user| format(CONTRIBUTOR, user: user) }.uniq

    unique_contributor_names.reject { |line| @rest.include?(line) }
  end

  def contributors
    @entries.values.join("\n")
            .scan(SIGNATURE).flatten
  end

  private

  def merge_entries(entry_map)
    all = @unreleased.merge(entry_map) { |_k, v1, v2| v1.concat(v2) }
    canonical = TYPE_TO_HEADER.values.to_h { |v| [v, nil] }
    canonical.merge(all).compact
  end

  def parse(content)
    ss = StringScanner.new(content)
    @header = ss.scan_until(FIRST_HEADER)
    @unreleased = parse_release(ss.scan_until(/\n(?=## )/m))
    @rest = ss.rest
  end

  # @return [Hash<type, Array<String>]]
  def parse_release(unreleased)
    unreleased
      .lines
      .map(&:chomp)
      .reject(&:empty?)
      .slice_before(HEADER)
      .to_h do |header, *entries|
        [HEADER.match(header)[1], entries]
      end
  end

  def parse_entries(path_content_map)
    changes = Hash.new { |h, k| h[k] = [] }
    path_content_map.each do |path, content|
      header = TYPE_TO_HEADER.fetch(TYPE_REGEXP.match(path)[1].to_sym)
      changes[header].concat(content.lines.map(&:chomp))
    end
    changes
  end
end
