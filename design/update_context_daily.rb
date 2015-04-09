#!/usr/bin/env ruby

require 'net/http'
require 'digest/md5'
require 'time'

# $server_pragma_http  = "http://www.pragma-ade.com" # context/(current|beta)/cont-tmf.zip"
# $server_pragma_ftp   = "ftp://ftp.pragma-ade.com"
# $server_pragma_rsync = "rsync://ctx.pragma-ade.nl" # rsync://ctx.pragma-ade.nl/$1/cont-tmf.zip

# http://stevelorek.com/how-to-shrink-a-git-repository.html
# http://stackoverflow.com/questions/14290113/git-pushing-code-to-two-remotes

$verbose = false
$verbose = true

$zip_path = '/context/mirror/context/zips/'
$git_path = '/context/mirror/context/git/'

# TODO: temporary for local testing only
$zip_path = File.join(Dir.getwd, "zips")
$git_path = File.join(Dir.getwd, "mojca", "context.git")
$ver_path = File.join(Dir.getwd, "versions")

# TODO: try to use /usr/bin/logger to log things

class LocalFile
	def initialize(path)
		if File.file?(path) then
			@path = File.expand_path(path)
			# @md5 = Digest::MD5.hexdigest(File.read(@path))
		else
			raise "invalid path #{path}"
		end
	end

	def dirname
		return File.dirname(@path)
	end

	def basename
		return File.basename(@path)
	end

	def md5
		if @md5 != nil then
			return @md5
		else
			@md5 = Digest::MD5.hexdigest(File.read(@path))
		end
	end

	def self.md5(path)
		if File.exists?(path) then
			return Digest::MD5.hexdigest(File.read(path))
		else
			return nil
		end
	end

	def self.contextversion(path)
		if File.exists?(path) and File.extname(path) == ".zip" then
			return `unzip -p #{path} tex/context/base/context.mkiv | grep def.contextversion `.gsub(/^.*\{(.*)\}.*$/m, '\1')
		else
			return nil
		end
	end
end

class ConTeXtVersion
	def initialize(zip_file, file_on_http_server)
		if $verbose then
			puts "### #{file_on_http_server} -> #{zip_file}"
		end
		@zip_file      = File.expand_path(zip_file)
		@zip_http_path = file_on_http_server

		# first check if file exists locally and initialize
		if File.exists?(@zip_file) then
			@zip_md5  = LocalFile.md5(@zip_file)
			@zip_time = File.mtime(@zip_file)
			@zip_size = File.size(@zip_file)

			if $verbose then
				puts "local file #{zip_file}\n\ttime: #{@zip_time}\n\tsize: #{@zip_size} bytes"
				puts "\tcontext_version: #{LocalFile.contextversion(@zip_file)}"
			end
		else
			@zip_md5  = nil
			@zip_time = nil
			@zip_size = 0

			if $verbose then
				puts "file #{zip_file} doesn't exist"
			end
		end

		@zip_new_md5  = nil
		@zip_new_time = nil
		@zip_new_size = 0

		@file_on_server_exists = nil
		@file_updated = false
	end


	def fetch_from_http(http)
		response = http.request_head(@zip_http_path)

		if $verbose then
			puts "trying to fetch #{@zip_http_path}"
		end

		case response
		when Net::HTTPSuccess
			# OK
			@file_on_server_exists = true
			if $verbose then
				puts "file #{@zip_http_path} is present on server"
			end
		when Net::HTTPNotFound
			# file doesn't exist
			@file_on_server_exists = false
			if $verbose then
				puts "file #{@zip_http_path} is NOT present on server"
			end
		else
			# there was some error that we might want to report
			stderr.puts "WARNING: unable to access #{file} on server: #{response}"
			@file_on_server_exists = nil
		end

		if @file_on_server_exists then
			this_time = Time.parse(response['last-modified'])
			this_size = response['content-length'].to_i
			if $verbose then
				puts "server file time: #{this_time}"
				puts "server file size: #{this_size}"
			end

			if this_size != @zip_size or (this_time <=> @zip_time) != 0 then
				if $verbose then
					puts "file time or size differ, fetching"
					puts "  sizes: #{this_size} #{@zip_size} #{this_size != @zip_size}"
					puts "  times: #{this_time} #{@zip_time} #{this_time != @zip_time}"
				end
				resp = http.get(@zip_http_path)
				this_md5 = Digest::MD5.hexdigest(resp.body)
				puts "md5: #{this_md5}"
				if this_md5 != @zip_md5 then
					if $verbose then
						puts "file md5sums differ, saving"
					end
					open(@zip_file, "wb") do |file|
						file.write(resp.body)
					end
					# TODO: only if successful
					@file_updated = true

					File.utime(this_time, this_time, @zip_file)
					@zip_new_md5  = this_md5
					@zip_new_time = this_time
					@zip_new_size = this_size
				else
					if $verbose then
						puts "file md5sums equal (this should not happen unless timestamps are corrupt)"
					end
				end
			else
				if $verbose then
					puts "file time and size are equal, won't download anything"
				end
			end
		end
		# if true then
		# 	# this was newer
		# end
	end
end

class ConTeXtVersionCurrent < ConTeXtVersion
	def initialize(zip_file)
		super(zip_file,"/context/current/cont-tmf.zip")
	end
end
class ConTeXtVersionBeta    < ConTeXtVersion
	def initialize(zip_file)
		super(zip_file,"/context/beta/cont-tmf.zip")
	end
end
class ConTeXtVersionTest    < ConTeXtVersion
	def initialize(zip_file)
		super(zip_file,"/context/latest/cont-tst.7z")
	end
end

# version_name: beta or stable
#
def commit_to_git(version_name, path_extracted_files, path_git)
	path_old = File.expand_path(path_git)
	path_new = File.expand_path(path_extracted_files)

	pwd = Dir.getwd

	filewithversion_old = File.join(path_old, 'tex', 'context', 'base', 'context.mkiv')
	filewithversion_new = File.join(path_new, 'tex', 'context', 'base', 'context.mkiv')

	if not (version_name == "beta" or version_name == "stable") then
		puts "ERROR: version name must be 'beta' or 'stable', but it is '#{version_name}'"
		return
	end

	if File.exists?(filewithversion_old) and File.exists?(filewithversion_new) then
		# TODO: simplify all this
		versionstring_old = `cat #{filewithversion_old} | grep def.contextversion`.gsub(/^.*\{(.*)\}.*$/m, '\1')
		versionstring_new = `cat #{filewithversion_new} | grep def.contextversion`.gsub(/^.*\{(.*)\}.*$/m, '\1')

		if versionstring_old =~ /(\d{4,4}).(\d{2,2}).(\d{2,2}) (\d{2,2}):(\d{2,2})/ then
			timestamp_old = Time.local($1,$2,$3,$4,$5)
		else
			puts "ERROR: version '#{versionstring_old}' cannot be parsed"
		end
		if versionstring_new =~ /(\d{4,4}).(\d{2,2}).(\d{2,2}) (\d{2,2}):(\d{2,2})/ then
			timestamp_new = Time.local($1,$2,$3,$4,$5)
		else
			puts "ERROR: version '#{versionstring_new}' cannot be parsed"
		end

		puts "version_old: #{versionstring_old}; timestamp: #{timestamp_old}"
		puts "version_new: #{versionstring_new}; timestamp: #{timestamp_new}"

		if timestamp_new > timestamp_old then
			ENV['GIT_AUTHOR_DATE']     = "#{timestamp_new}"
			ENV['GIT_COMMITTER_DATE']  = "#{timestamp_new}"

			# alternatively we could use
			# git config user.name  'Hans Hagen'
			# git config user.email 'pragma@wxs.nl'
			ENV['GIT_AUTHOR_NAME']     = 'Hans Hagen'
			ENV['GIT_COMMITTER_NAME']  = 'Hans Hagen'
			ENV['GIT_AUTHOR_EMAIL']    = 'pragma@wxs.nl'
			ENV['GIT_COMMITTER_EMAIL'] = 'pragma@wxs.nl'

			Dir.chdir(path_new)
			system('chmod +x scripts/context/stubs/unix/*')
			system('chmod +x scripts/context/stubs/mswin/*.exe')
			system('chmod +x scripts/context/stubs/win64/*.exe')

			Dir.chdir(path_old)
			system('git checkout master')
			system("rsync -av --delete --exclude '.git' #{path_new}/ ./")
			system('git add -A')
			system("git commit -m '#{version_name} #{versionstring_new}'")

			## every now and then to shrink the repository size
			#
			# rm -rf .git/refs/original/
			# git reflog expire --expire=now --all
			# git gc --prune=now
			# git gc --aggressive --prune=now
		else
			puts "ERROR: there is something wrong with timestamps (old: #{timestamp_old}, new: #{timestamp_new})"
		end
	else
		puts "ERROR: '#{filewithversion_old}' or '#{filewithversion_new}' doesn't exist"
	end

	Dir.chdir(pwd)
end

# TODO: check if one can connect to server at all
Net::HTTP.start("www.pragma-ade.com", 80) do |http|
	versions = [
		ConTeXtVersionCurrent.new(File.join($zip_path, "cont-tfm-current.zip")),
		ConTeXtVersionBeta.new(   File.join($zip_path, "cont-tfm-beta.zip"   )),
		ConTeXtVersionTest.new(   File.join($zip_path, "cont-tst.7z"         )),
	]
	versions.each do |context_version|
		if $verbose then
			puts
		end
		context_version.fetch_from_http(http)
	end

	# TODO
	# - check if context version has changed at all
	# - for those zips that changed, remove the old extracted contents and unzip again
	# - check which of beta/stable is more recent and sync + commit that one
	# - handle situations when beta is missing from Hans' server
	#
	commit_to_git("beta", File.join($ver_path, 'beta'), $git_path)
	# commit_to_git("stable", File.join($ver_path, 'current'), $git_path)
end

# git filter-branch --tree-filter 'git ls-files -z scripts/context/stubs/*/*.exe | xargs -0 chmod +x' -- --all
# git filter-branch --tree-filter 'git ls-files -z scripts/context/stubs/unix/*  | xargs -0 chmod +x' -- --all
