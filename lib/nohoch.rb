# git log --pretty=%an --numstat -- lib/mix/tasks/backfill_first_response_times_nsa.ex
#
module Nohoch
  require 'optparse'
  require 'pathname'
  require 'io/console'
  require 'digest'

  def Nohoch.call
    CLI.new()
  end

  class CLI
    attr_reader :options, :dir, :out, :files, :user_file_stats

    def initialize
      @options = {}
      @user_file_stats = UserFileStats.new()
      @out = []
      parse_opts
      set_dir

      get_files
      stats
      # p @options
      # parse_stats
      # @user_file_stats.stats.sort_by {|_, file_stat| -file_stat.added}.each {|_, v| p v.to_s}
      # @user_file_stats.top("values-prod-usw2-kubernetes.yaml", 5).each_with_index {|e, i| p "[#{i+1}] #{e.to_s}"}

      # random_file = @user_file_stats.files.sample
      # @user_file_stats.top(random_file, 5).each_with_index {|e, i| p "[#{i+1}] #{e.to_s}"}
      @user_file_stats.all_top(5).each do |_, file_stats|
        file_stats.each_with_index {|e, i| p "[#{i+1}] #{e.to_s}"}
      end
    end

    def parse_opts
      OptionParser.new do |opts|
        opts.banner = "Usage: nohoch [options]"
        opts.on("-v", "--[no-]verbose", "Run verbosely") { |v| @options[:verbose] = v }
      end.parse!
    end

    def set_dir
      dir = Pathname.new(ARGV[0])
      raise "Not a dir" unless dir.directory?
      raise "Directory does not contain an initialized git directroy" unless dir.join(".git").directory?
      @dir = dir
    end

    def stats
      # @files.first(100).each do |filename|
      @files.each do |filename|
        Dir.chdir(@dir){
          # git log --no-merges --pretty=%an --numstat -10
          IO.popen(["git", "--no-pager", "log", "--no-merges", "--pretty=%an", "--numstat", "--", filename, "origin/master", :err=>[:child, :out]]) {|git_io|
            # TODO check that the output is in the correct format and raise exception if it is not.
            # capture the helpful debug info.
            result = git_io.read
            p result
            out = result.split(/\n+/)
            out.each_slice(2) do |user, stat|
              matches = /(?<added>[\d-]+)\t(?<deleted>[\d-]+)\t(?<file>.*)/.match(stat)
              added = matches[:added].to_i
              deleted = matches[:deleted].to_i
              file = matches[:file].chomp

              # puts "#{user} added #{added} lines and deleted #{deleted} lines in #{file}"
              @user_file_stats.add(FileStat.new(user.chomp, added, deleted, file))
            end
          }
        }
      end
    end


    def get_files
      Dir.chdir(@dir){
        # git ls-tree -r master --name-only
        IO.popen(["git", "ls-tree", "-r", "origin/master", "--name-only", :err=>[:child, :out]]) {|git_io|
          @files = git_io.read.split(/\n+/)
        }
      }
    end
  end

  class FileStat
    attr_reader :user, :file, :user_id
    attr_accessor :added, :deleted

    def initialize(user, added, deleted, file)
      @user = user
      @added = added
      @deleted = deleted
      @file = file
      @user_id = Digest::SHA256.base64digest(user.downcase)
    end

    def to_s
      "#{@file} #{@user} +#{@added} -#{@deleted}"
    end
  end

  class UserFileStats
    attr_reader :stats

    def initialize
      @stats = {}
    end

    def add(file_stat)
      key = file_stat.user_id + file_stat.file
      if @stats[key]
        @stats[key].added += file_stat.added
        @stats[key].deleted += file_stat.deleted
      else
        @stats[key] = file_stat
      end
    end

    def user_stats(file)
      @stats.select { |_, file_stat| file_stat.file == file }
    end

    def all_top(n)
      result = {}
      files.each {|f| result[f] = top(f, n) }
      result
    end

    def top(file, n)
      user_stats(file).sort_by {|_, file_stat| -file_stat.added}[0..n-1].to_h.values
    end


    def files
      @stats.values.uniq { |file_stat| file_stat.file }.map {|file_stat| file_stat.file }
    end

    def users
      @stats.values.uniq { |file_stat| file_stat.user_id }.map {|file_stat| file_stat.user }
    end
  end
end