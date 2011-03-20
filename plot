set title "Latency vs. request rate and time"
set xtics ("1" 0, "2" 1, "4" 2, "8" 3, "16" 4)
set boxwidth 0.3
set style fill solid 1.00 border -1
set style histogram errorbars
set style data histograms

set xlabel "Rate /s"
set ylabel "Latency /ms"

plot "parsedLogs/pastry_histogram_t1.csv" using 2:3 title '1 node per host', \
     "" using 4:5 title '2 nodes per host', \
     "" using 6:7 title '4 nodes per host', \
     "" using 8:9 title '8 nodes per host'

#### PASTRY
### 1 nodes

set xlabel "Time /ms"

plot "parsedLogs/pastry_1_t1_against_time_for_rate1.csv" using 1:3 title 'Latency change at rate 1/s', \
     "" using 1:5 title 'Nodes involved change at rate 1/s'
plot "parsedLogs/pastry_1_t1_against_time_for_rate2.csv" using 1:3 title 'Latency change at rate 2/s', \
     "" using 1:5 title 'Nodes involved change at rate 2/s'
plot "parsedLogs/pastry_1_t1_against_time_for_rate4.csv" using 1:3 title 'Latency change at rate 4/s', \
     "" using 1:5 title 'Nodes involved change at rate 4/s'
plot "parsedLogs/pastry_1_t1_against_time_for_rate8.csv" using 1:3 title 'Latency change at rate 8/s', \
     "" using 1:5 title 'Nodes involved change at rate 8/s'
plot "parsedLogs/pastry_1_t1_against_time_for_rate16.csv" using 1:3 title 'Latency change at rate 16/s', \
     "" using 1:5 title 'Nodes involved change at rate 16/s'
     

### 2 nodes
plot "parsedLogs/pastry_2_t1_against_time_for_rate1.csv" using 1:3 title 'Latency change at rate 1/s', \
     "" using 1:5 title 'Nodes involved change at rate 1/s'
plot "parsedLogs/pastry_2_t1_against_time_for_rate2.csv" using 1:3 title 'Latency change at rate 2/s', \
     "" using 1:5 title 'Nodes involved change at rate 2/s'
plot "parsedLogs/pastry_2_t1_against_time_for_rate4.csv" using 1:3 title 'Latency change at rate 4/s', \
     "" using 1:5 title 'Nodes involved change at rate 4/s'
plot "parsedLogs/pastry_2_t1_against_time_for_rate8.csv" using 1:3 title 'Latency change at rate 8/s', \
     "" using 1:5 title 'Nodes involved change at rate 8/s'
plot "parsedLogs/pastry_2_t1_against_time_for_rate16.csv" using 1:3 title 'Latency change at rate 16/s', \
     "" using 1:5 title 'Nodes involved change at rate 16/s'


### 4 nodes
plot "parsedLogs/pastry_4_t1_against_time_for_rate1.csv" using 1:3 title 'Latency change at rate 1/s', \
     "" using 1:5 title 'Nodes involved change at rate 1/s'
plot "parsedLogs/pastry_4_t1_against_time_for_rate2.csv" using 1:3 title 'Latency change at rate 2/s', \
     "" using 1:5 title 'Nodes involved change at rate 2/s'
plot "parsedLogs/pastry_4_t1_against_time_for_rate4.csv" using 1:3 title 'Latency change at rate 4/s', \
     "" using 1:5 title 'Nodes involved change at rate 4/s'
plot "parsedLogs/pastry_4_t1_against_time_for_rate8.csv" using 1:3 title 'Latency change at rate 8/s', \
     "" using 1:5 title 'Nodes involved change at rate 8/s'

plot "parsedLogs/pastry_2_t1_against_time_for_rate4.csv" using 1:4 title 'Latency change at rate 8/s'


#### PASTRY
### 8 nodes
plot "parsedLogs/pastry_8_t1_against_time_for_rate1.csv" using 1:3 title 'Latency change at rate 1/s', \
     "" using 1:5 title 'Nodes involved change at rate 1/s'
plot "parsedLogs/pastry_8_t1_against_time_for_rate2.csv" using 1:3 title 'Latency change at rate 2/s', \
     "" using 1:5 title 'Nodes involved change at rate 2/s'
plot "parsedLogs/pastry_8_t1_against_time_for_rate4.csv" using 1:3 title 'Latency change at rate 4/s', \
     "" using 1:5 title 'Nodes involved change at rate 4/s'
plot "parsedLogs/pastry_8_t1_against_time_for_rate8.csv" using 1:3 title 'Latency change at rate 8/s', \
     "" using 1:5 title 'Nodes involved change at rate 8/s'




#####################################################
#### Chord
### 1 nodes
plot "parsedLogs/chord_1_t1_against_rate.csv" using 1:2:3 title '8 nodes per host' with boxerrorbars
plot "parsedLogs/chord_1_t2_against_rate.csv" using 1:2:3 title '8 nodes per host' with boxerrorbars

plot "parsedLogs/chord_1_t1_against_time_for_rate1.csv" using 1:3 title 'Latency change at rate 1/s', \
     "" using 1:5 title 'Nodes involved change at rate 1/s'
plot "parsedLogs/chord_1_t1_against_time_for_rate2.csv" using 1:3 title 'Latency change at rate 2/s', \
     "" using 1:5 title 'Nodes involved change at rate 2/s'


### 2 nodes
plot "parsedLogs/chord_2_t1_against_rate.csv" using 1:2:3 title '8 nodes per host' with boxerrorbars

plot "parsedLogs/chord_2_t1_against_time_for_rate1.csv" using 1:3 title 'Latency change at rate 1/s', \
     "" using 1:5 title 'Nodes involved change at rate 1/s'
plot "parsedLogs/chord_2_t1_against_time_for_rate2.csv" using 1:3 title 'Latency change at rate 2/s', \
     "" using 1:5 title 'Nodes involved change at rate 2/s'


### 4 nodes
plot "parsedLogs/chord_4_t1_against_rate.csv" using 1:2:3 title '8 nodes per host' with boxerrorbars

plot "parsedLogs/chord_4_t1_against_time_for_rate1.csv" using 1:3 title 'Latency change at rate 1/s', \
     "" using 1:5 title 'Nodes involved change at rate 1/s'
plot "parsedLogs/chord_4_t1_against_time_for_rate2.csv" using 1:3 title 'Latency change at rate 2/s', \
     "" using 1:5 title 'Nodes involved change at rate 2/s'
plot "parsedLogs/chord_4_t1_against_time_for_rate4.csv" using 1:3 title 'Latency change at rate 4/s', \
     "" using 1:5 title 'Nodes involved change at rate 4/s'
plot "parsedLogs/chord_4_t1_against_time_for_rate8.csv" using 1:3 title 'Latency change at rate 8/s', \
     "" using 1:5 title 'Nodes involved change at rate 8/s'
plot "parsedLogs/chord_4_t1_against_time_for_rate16.csv" using 1:3 title 'Latency change at rate 16/s', \
     "" using 1:5 title 'Nodes involved change at rate 16/s'


### 8 nodes
plot "parsedLogs/chord_8_t1_against_rate.csv" using 1:2:3 title '8 nodes per host' with boxerrorbars

plot "parsedLogs/chord_8_t1_against_time_for_rate1.csv" using 1:3 title 'Latency change at rate 1/s', \
     "" using 1:5 title 'Nodes involved change at rate 1/s'
plot "parsedLogs/chord_8_t1_against_time_for_rate2.csv" using 1:3 title 'Latency change at rate 2/s', \
     "" using 1:5 title 'Nodes involved change at rate 2/s'
plot "parsedLogs/chord_8_t1_against_time_for_rate4.csv" using 1:3 title 'Latency change at rate 4/s', \
     "" using 1:5 title 'Nodes involved change at rate 4/s'
plot "parsedLogs/chord_8_t1_against_time_for_rate8.csv" using 1:3 title 'Latency change at rate 8/s', \
     "" using 1:5 title 'Nodes involved change at rate 8/s'
plot "parsedLogs/chord_8_t1_against_time_for_rate16.csv" using 1:3 title 'Latency change at rate 16/s', \
     "" using 1:5 title 'Nodes involved change at rate 16/s'
