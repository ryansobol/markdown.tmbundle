class String
	
	def add_newline()
		if self !~ /\n$/m
			self + "\n"
		else
			self
		end
	end
	
end


module Markdown
	
	class Insert
		
		def initialize(str)
			@str = str
		end
		
		
		def length
			str.length
		end
		
		
		def to_s
			@str.to_s
		end
	end
	
	
	class ListLine
		attr_accessor :line, :indent

		
		def initialize(line, indent, str)
			@line = line
			@indent = indent
			@str = [str]
		end
		
		
		def [](arg)
			if arg.kind_of?(Range)
				# adjust the range by the indent
				if (arg.begin >= 0 and arg.begin < @indent.length) and (arg.end >= 0 and arg.end < @indent.length)
					return ""
				end
				
				newbegin = if arg.begin >= 0 then [arg.begin - @indent.length, 0].max() else arg.begin end
				newend = if arg.end >= 0 then [arg.end - @indent.length, 0].max() else arg.end end
				return self.to_s()[Range.new(newbegin, newend, arg.exclude_end?)]
			elsif arg.kind_of?(Integer)
				if arg < 0
					return self.to_s()[arg]
				else
					return self.to_s()[[arg - @indent.length(), 0].max()]
				end
			else
				return self.to_s()[arg]
			end
		end
		
		
		def str=(newstr)
			@str = [newstr]
		end
		
		
		def str()
			to_s()
		end
		
		
		def rawstr()
			@str
		end
		
		
		def rawstr=(newrawstr)
			@str = newrawstr
		end
		
		
		def insert(pos, insert)
			index = 0
			newstr = []
			@str.each() do |s|
				if index + s.length < pos
					index += s.length
					newstr << s
				elsif index <= pos and index + s.length >= pos
					pos -= index
					newstr << s[0...pos]
					newstr << Insert.new(insert)
					newstr << s[pos..-1]
				else
					newstr << s
				end
			end
			@str = newstr
			
			self
		end
		
		
		def to_s()
			@str.map { |s| s.to_s }.join()
		end
	end
	
	
	class List
		class SubList < StandardError
		end

		
		attr_accessor :line, :indent, :numbered
		
		@@sublistregex = /^\s+([0-9]+\.|\*)\s/

		# This should never be called unless you know what you are doing.  It is used
		# internally to create sublists.  Generally you will want to call List.parse(str)
		# instead
		def initialize(line=nil, indent=nil, numbered=nil, entries = [])
			@line = line
			@indent = indent
			@numbered = numbered
			@entries = []
			entries.each() do |e|
				@entries << e
			end
		end
		
		
		def add(entry)
			@entries << entry
			self
		end
		
		
		def <<(entry)
			add(entry)
			self
		end
		
		
		def length()
			@entries.inject(0) { |t, e| t + e.inject(0) { |t, l| if l.kind_of?(List) then t + l.length else t + 1 end } }
		end

				
		def [](index)
			@entries[index]
		end
		
		
		# yields each str in turn to &block and replaces the result.  Also
		# performs pending insertions after the yield (to avoid escaping insertions)
		def map!(&block)
			@entries.each() do |e|
				e.each_index() do |i|
					l = e[i]
					if l.kind_of?(ListLine)
						newrawstr = []
						l.rawstr.each() do |s|
							if s.kind_of?(String)
								s = yield(s)
							end
							newrawstr << s
						end
						e[i].rawstr = newrawstr
					else
						l.map!(&block)
					end
				end
			end
			
			self
		end
		
		
		# indents the item marked by the original input line
		def indent_entry(line)
			curline = 0
			@entries.each_index() do |i|
				@entries[i].each_index do |li|
					l = @entries[i][li]
					if l.kind_of?(ListLine)
						if l.line == line
							@entries[i] = List.new(-1, newindent, self.numbered, [secondpart])
							break
						elsif l.line <= line and l.line + l.length >= line
							l.indent(line - l.line)
						end
					end
				end
			end
			
			self
		end
		
		
		# breaks the list at line, pos in the original input
		# inserts insert at the break point and filters everything
		# else through block.  If aslist is true, then the break
		# item is inserted as a new list
		def break(line, pos, insert = "$0", aslist = false, &block)
			curline = 0
			@entries.each_index() do |i|
				@entries[i].each_index do |li|
					l = @entries[i][li]
					if l.kind_of?(ListLine)
						if l.line == line
							breakentry = @entries[i]
							breakline = @entries[i][li]
							newentries = []
							
							firstpart = breakentry[0...li] << ListLine.new(-1, breakline.indent, (breakline[0...pos].add_newline()))
							newentries << firstpart
							
							secondpart = [ListLine.new(-1, breakline.indent, breakline[pos..-1].lstrip().add_newline())] + breakentry[li+1..-1]

							if firstpart.map { |l| l.to_s() }.join().strip == "" and secondpart.map { |l| l.to_s() }.join().strip() != ""
								firstpart[-1].insert(0, " " + insert)
								secondpart[0].insert(0, " ")
							else
								secondpart[0].insert(0, " " + insert)
							end
							
							if aslist
								newindent = increase_indent(self.indent)
								secondpart = List.new(-1, newindent, self.numbered, [secondpart])
								firstpart << secondpart
							else
								newentries << secondpart
							end

							@entries = @entries[0...i] + newentries + @entries[i+1..-1]
							break
 						end
					elsif l.line <= line and l.line + l.length >= line
						l.break(line - l.line, pos, insert, aslist)
					end
				end
			end

			if block
				self.map!(&block)
			end
			
			self
		end
		
		
		# parses the list into a full structure
		def List.parse(str, line = 0)
			list = List.new()
			list.indent = str[/^(\s*)/, 1].to_s()
			list.numbered = /^\s*([0-9])/.match(str.to_a[0])
			list.line = line
			itemregex = /^(#{Regexp.escape(list.indent)}#{if list.numbered then "[0-9]+\\." else "\\*" end})(\s.*)/

			entry = []
			linenumber = -1
			begin
				lines = str.to_a()
				lines.each_index() do |i|
					line = lines[i]
					linenumber += 1
					
					# we might be in an indented sublist, if the indent goes down, and the line isn't blank, return the list and the remainder
					if list.indent.length > 0 && line[/^(\s*)/, 1].to_s.length < list.indent.length && line.strip() != ""
						list << entry
						return [list, lines[i..-1].join()]
					end
					
					if itemregex.match(line)
						if entry.length > 0
							list << entry
						end
						entry = [ListLine.new(linenumber, $1, $2 + "\n")]
					else
						if @@sublistregex.match(line)
							sublist, str = List.parse(lines[i..-1].join(), i)
							entry << sublist
							linenumber += sublist.length - 1
							raise SubList
						else
							entry << ListLine.new(linenumber, "", line)
						end
					end
				end
				list << entry
			rescue SubList
				retry
			end
			
			list
		end


		def to_s()
			str = ""
			@entries.each_index() do |i|
				str << @indent
				if @numbered
					str << "#{i+1}."
				else
					str << "*"
				end
				
				str << @entries[i].map { |e| e.to_s() }.join()
			end
			
			str
		end
		
		private
		
		# creates a new, deper indent based on indent
		def increase_indent(indent)
			if indent =~ /\t/
				"\t#{indent}"
			else
				" " * ENV['TM_TAB_SIZE'].to_i + indent
			end
		end
	end
	
end
