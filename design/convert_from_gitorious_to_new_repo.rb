#!/usr/bin/env ruby

# TODO: there is something weird in 480ea84
# \edef\contextversion{2010.04.29 22:30}

# TODO:
# - downcase filename
# - parse context.tex for proper date & time
# - check the original zips for hour for oldest zips
# - if there is no TDS, fix it
# - for year 2006, add date to strings with "stable/beta"; for the third one, change date in context;
#   for the first 2006 release, edit date in context.tex; always take the true date
#
# - try to compare different sha with the same context version to make sure that they are the same
#
# - 2004.9.17 & earlier have single digit context days & months
# remove tex/context/base/TRANS.TBL


class History < Hash
	def add_revision(revision)
		if self[revision.time] == nil then
			self[revision.time] = Array.new
		end
		self[revision.time].push(revision)
	end
	def add_revision_by_name(revision,original_name)
		name = ""
		if name != nil then
			name = original_name.gsub(/[.](\d{1,1})([^\d])/,'.0\1\2').gsub(/[.](\d{1,1})$/,'.0\1')
		end
		if self[name] == nil then
			self[name] = Array.new
		end
		self[name].push(revision)
	end
end

class Revision
	class Stable
	end
	class Beta
	end
	class Master
	end

	def initialize(repo,sha,comment)
		@repo = repo
		@sha = sha
		@original_comment = comment
		if comment =~ /beta/ then
			@type = Beta.new
		elsif comment =~ /stable/ then
			@type = Stable.new
		elsif sha == "master" then
			@type = Master.new
		else
			raise "there is a problem in comment for #{sha}: '#{comment}'; should be beta or current"
		end
		if comment != nil then
			@original_comment = comment.gsub(/-/, '.')
		end
		@time = nil
	end
	def to_s
		string = " sha <#{@sha}> "
		case @type
		when Stable
			string = string + "<stable> "
		when Beta
			string = string + "<beta>   "
		else
			raise "wrong type of revision"
		end
		string = string + "name <#{@original_comment}>"
		return string
	end
	def new_comment
		string = ""
		case @type
		when Stable
			string = string + "stable "
		when Beta
			string = string + "beta "
		else
			raise "wrong type of revision"
		end
		if @time.strftime("%H%M") == "0000" and @time.year < 2006 then
			string = string + @time.strftime("%Y.%m.%d")
		else
			string = string + @time.strftime("%Y.%m.%d %H:%M")
		end
	end

	def switch_to_this
		system("git checkout #{@sha} 2> /dev/null")
		system("git reset --hard > /dev/null")
		system("git clean -f -d 2> /dev/null")
		# puts
		# puts Dir.pwd
		# puts "trying to get into #{@sha}"
		# puts "git status"
		# puts `git status`
		# # system("git clean -f")
		# # system("git reset --hard")
		# system("git checkout #{@sha}")
		# system("git reset --hard")
		# system("git clean -f")
	end

	def get_time_string
		if @time_string == nil then
			version = get_version
			if version =~ /(\d{4,4}).(\d{2,2}).(\d{2,2}) (\d{2,2}):(\d{2,2})/ then
				@time = Time.local($1,$2,$3,$4,$5)
				@time_string = @time.strftime("%Y-%m-%d %H:%M %z")
			else
				@time_string = ""
				puts "ERROR: version '#{version}' cannot be parsed"
			end
		end
		return @time_string
	end
	def get_version
		if @version != nil then
			return @version
		end

		# pwd = Dir.pwd
		Dir.chdir(@repo.path)
		switch_to_this
		version = nil
		# puts
		# puts @original_comment
		# puts
		if @original_comment == "stable 1999.03.31" then
			set_version("1999.03.31") # 14:04
		elsif @original_comment == "2006.01.09" then
			set_version("2006.01.09 11:48")
		elsif File.exists?("tex/context/base/context.tex") then
			File.open("tex/context/base/context.tex").grep(/def.*contextversion\{(.*)\}/) do |s|
				version = $1
				set_version(version)
			end
			if version == nil then
				puts "    WARNING: version undefined in #{@sha} @ #{@original_comment}"
				set_version(@original_comment.gsub(/(stable|beta) /,""))
			end
		elsif File.exists?("tex/context/base/context.mkiv") then
			File.open("tex/context/base/context.mkiv").grep(/def.*contextversion\{(.*)\}/) do |s|
				version = $1
				set_version(version)
			end
			if version == nil then
				puts "    WARNING: version undefined in #{@sha} @ #{@original_comment}"
				set_version(@original_comment.gsub(/(stable|beta) /,""))
			end
		elsif File.exists?("context.tex")
			puts "    WARNING: context.tex is in root in #{@sha} @ #{@original_comment}"
			File.open("context.tex").grep(/def.*contextversion\{(.*)\}/) do |s|
				version = $1
				set_version(version)
			end
			if version == nil then
				# puts "    WARNING: version undefined in #{@sha} @ #{@original_comment}"
				set_version(@original_comment.gsub(/(stable|beta) /,""))
			end
		else
			puts "    I cannot find context.tex for #{@sha} @ #{@original_comment}"
		end
		# Dir.chdir(pwd)
		return @version
	end
	def set_version(version)
		@version = version#.gsub(/[-]/, '.')
		if version =~ /(\d{4,4}).(\d{2,2}).(\d{2,2}) (\d{2,2}):(\d{2,2})/ then
			@time = Time.local($1,$2,$3,$4,$5)
			@new_comment = @time.strftime("%Y.%m.%d %H:%M")
			# puts "    #{version}  ##  #{@time.strftime("%Y.%m.%d %H:%M %z %Z")}  ##  #{@original_comment}  ##  #{@sha}"
		elsif version =~ /(\d{4,4}).(\d{2,2}).(\d{2,2})/ then
			@time = Time.local($1,$2,$3)
			# puts "    #{version}  ##  #{@time.strftime("%Y.%m.%d %H:%M %z %Z")}  ##  #{@original_comment}  ##  #{@sha}"
		elsif version =~ /(\d{4,4}).(\d{1,2}).(\d{1,2})/ then
			@time = Time.local($1,$2,$3)
			# puts "    #{version}  ##  #{@time.strftime("%Y.%m.%d %H:%M %z %Z")}  ##  #{@original_comment}  ##  #{@sha}"
		else
			puts "invalid time in #{version} (#{sha})"
		end
		if @time != nil then
			puts "    #{version.ljust(16)}  ##  #{@original_comment.rjust(23)}  ##  #{new_comment.rjust(23)}  ##  #{@sha}" #{@time.strftime("%Y.%m.%d %H:%M %z %Z").ljust(28)}
		else
			puts "    #{version.ljust(16)}  ##  #{@original_comment.rjust(23)}  ##  #{new_comment.rjust(23)}  ##  #{@sha}"
		end
		if @time.strftime("%Y.%m.%d") != @original_comment.gsub(/(stable|beta) /, "").gsub(/ \d\d:\d\d/, "") then
			puts "    WARNING: different strings for '#{@original_comment}' and #{@time.strftime("%Y.%m.%d %H:%M")}"
		end
	end
	def transfer_revision(path)
		command = "rsync -av --delete --exclude '.git' ./ #{path}"
		puts command
		system(command)

		ENV['GIT_AUTHOR_DATE']    = get_time_string
		ENV['GIT_COMMITTER_DATE'] = get_time_string

		pwd = Dir.pwd
		Dir.chdir(path)
		command = "git add -A"
		system(command)
		
		command = "git commit -m \"#{new_comment}\""
		puts command
		system(command)
		Dir.chdir(pwd)
	end

	attr_reader :sha, :version, :original_comment, :time
end

class Git
	def initialize(path)
		@path = File.expand_path(path, Dir.pwd)
		if not File.directory?(@path) then
			raise "'#{@path}' is not a valid directory"
		end
		@master = Revision.new(self,"master",nil)
		@history_by_name = History.new
		@history_small = History.new
		@history_small_list = Array.new
	end

	def get_revisions
		# pwd = Dir.pwd
		Dir.chdir(@path)
		@master.switch_to_this
		# system("git checkout master")
		logs = `git log --pretty=oneline`.split(/\n/)
		# Dir.chdir(pwd)

		revisions = Array.new
		logs.each do |line|
			if line =~ /^((\d|[a-f]|[A-F])+) (.*)$/ then
				sha  = $1
				name = $3
				revision = Revision.new(self,sha,name)
				# puts revision
				# revision.get_version
				revisions.push(revision)
				history_by_name.add_revision_by_name(revision,name)
			else
				puts "what is wrong with '#{line.chomp}'?"
			end
		end
		history_by_name.sort.sort{ |a, b| a.first.gsub(/(beta|stable) /, "") <=> b.first.gsub(/(beta|stable) /, "") }.each do |time,list|
			revision = list.last
			history_small.add_revision_by_name(revision,time)
			history_small_list.push([time,revision])
		end
		return revisions
	end

	attr_reader :path, :history_by_name, :history_small, :history_small_list
end

$global_pwd = Dir.pwd

old_repo = Git.new("patrick/context")
new_repo = Git.new("gitorious/context")

# revisions = old.get_revisions
revisions = new_repo.get_revisions

# new_repo.history_by_name.sort{ |a, b| a.first.gsub(/(beta|stable) /, "") <=> b.first.gsub(/(beta|stable) /, "") }.each do |t,h|
# 	puts "'#{t}'"
# 	h.each do |rev|
# 		puts "    - #{rev.sha}"
# 	end
# 	# puts t.strftime("> %Y.%m.%d %H:%M %z %Z")
# 	# h.each do |rev|
# 	# 	puts "  - <#{rev.sha}> <#{rev.version}> <#{rev.original_comment}>"
# 	# end
# end

# puts new_repo.history_small.length

# old.history_small_list[3..400].each do |list|
# 	time = list[0]
# 	rev  = list[1]
# 	rev.get_version
# 	rev.transfer_revision(File.join($global_pwd, "patrick", "new"))
# end

# 278
puts "number of revisions in gitorious: #{new_repo.history_small_list.length}"

# 331-407, next time I need to do from 407 on ...
# 407-418, next time I need to do from 418 on ...
# 420-619, next time I need to do from 620 on ...
new_repo.history_small_list[625..943].each do |list|
	time = list[0]
	rev  = list[1]
	puts ": #{list[0]} #{list[1]}"
	rev.get_version
#	# UNCOMMENT THIS
	rev.transfer_revision(File.join($global_pwd, "patrick", "new"))
end

# git gc --aggressive
