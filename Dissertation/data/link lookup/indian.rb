File.open("indian.txt", "r") do |file|
	while(line = file.gets) do
		values = line.chomp.split(/\s+/).map do |num|
			mb = (num.to_f * 30000 / (1024 * 1024)).round.to_i.to_s
			while mb.length < 3 do
				mb = "0#{mb}"
			end
			"#{num} & #{mb[0...(mb.length - 2)]}.#{mb[-2..(mb.length)]}"
		end
		print " & "
		print values.join(" & ")
		print " \\\\\n\n"
	end
end