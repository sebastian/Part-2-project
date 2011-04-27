print "plot"
plots = []
dht = "pastry"
# Fix either nodes or rate to get more interesting graphs
nodes = 0
0.upto(7).each do |rate|
	plots << "'output/summary/#{dht}#{2 ** nodes}rate#{2 ** rate}/cdf.csv' u 1:2 t \"#{2 ** nodes} nodes at rate #{2 ** rate}\" with lines"
end
puts plots.join(", \\\n")
