#search and analyze twitter data, by Joseph Holler, 2019, with alterations by Ben Dohan, 2019
#following tutorial at https://www.earthdatascience.org/courses/earth-analytics/get-data-using-apis/use-twitter-api-r/
#also get advice from the rtweet page: https://rtweet.info/
#to do anything, you first need a twitter API token: https://rtweet.info/articles/auth.html 

#install packages for twitter, census, data management, and mapping
install.packages(c("rtweet","tidycensus","tidytext","maps","RPostgres","igraph","tm", "ggplot2","RColorBrewer","rccmisc","ggraph"))


#initialize the libraries
library(rtweet)
library(igraph)
library(dplyr)
library(tidytext)
library(tm)
library(tidyr)
library(ggraph)
library(tidycensus)
library(ggplot2)
library(RPostgres)
library(RColorBrewer)
library(DBI)
library(rccmisc)

help(rtweet) # put a library name or function in the help function to get help on anything!

#get a Census API here: https://api.census.gov/data/key_signup.html
#replace the key text 'yourkey' with your own key!
Counties <- get_estimates("county",product="population",output="wide",geometry=TRUE,keep_geo_vars=TRUE, key="yourkey")
############# TEXT / CONTEXTUAL ANALYSIS ############# 
#turn dorian tweets text into plain text
dorian$text <- plain_tweets(dorian$text)

#seperate each individual word in the tweet texts, removing punctuation and converting to lowercase and adding tweet ids to words
dorianText <- select(dorian,text)
dorianWords <- unnest_tokens(dorianText, word, text)

# how many words do you have including the stop words?
count(dorianWords)

#create list of stop words (useless words) and add "t.co" twitter links to the list
data("stop_words")
stop_words <- stop_words %>% add_row(word="t.co",lexicon = "SMART")

#remove stop words from the tweets
dorianWords <- dorianWords %>%
  anti_join(stop_words) 

# how many words after removing the stop words?
count(dorianWords)

#graph the number of times words were used in tweets about dorian
dorianWords %>%
  count(word, sort = TRUE) %>%
  top_n(15) %>%
  mutate(word = reorder(word, n)) %>%
  ggplot(aes(x = word, y = n)) +
  geom_col() +
  xlab(NULL) +
  coord_flip() +
  labs(x = "Count",
       y = "Unique words",
       title = "Count of unique words found in tweets")

#remove stopwords and punctuation, convert to lowercase, add tweet ids to words
dorianPairs <- dorian %>% select(text) %>%
  mutate(text = removeWords(text, stop_words$word)) %>%
  unnest_tokens(paired_words, text, token = "ngrams", n = 2)

#find which words were associated in the tweets
dorianWordPairs <- separate(dorianPairs, paired_words, c("word1", "word2"),sep=" ")
dorianWordCount <- dorianWordPairs %>% count(word1, word2, sort=TRUE)

#graph a word cloud with space indicating association between words (30 use minimum)
dorianWordCount %>%
  filter(n >= 30) %>%
  graph_from_data_frame() %>%
  ggraph(layout = "fr") +
  # geom_edge_link(aes(edge_alpha = n, edge_width = n)) +
  geom_node_point(color = "darkslategray4", size = 3) +
  geom_node_text(aes(label = name), vjust = 1.8, size = 3) +
  labs(title = "Word Network: Tweets about Hurricane Dorian",
       subtitle = "September 2019 ",
       x = "", y = "") +
  theme_void()


############### UPLOAD RESULTS TO POSTGIS DATABASE ###############

#Connectign to Postgres
#Create a con database connection with the dbConnect function.
#Change the database name, user, and password to your own!
con <- dbConnect(RPostgres::Postgres(), dbname='benjamin', host='artemis', user='benjamin', password='OS2019') 

#list the database tables, to check if the database is working
dbListTables(con) 

#create a simple table for uploading
dorian <- select(dorian,c("user_id","status_id","text","lat","lng"),starts_with("place"))

#write data to the database
dbWriteTable(con,'dorian', dorian, overwrite=TRUE)
dbWriteTable(con,'november', november, overwrite=TRUE)

#make all lower-case names for this table
counties <- lownames(Counties)
dbWriteTable(con,'counties',counties, overwrite=TRUE)
#SQL to update geometry column for the new table: select populate_geometry_columns('necounties'::regclass);

#disconnect from the database
dbDisconnect(con)

#export twitter id's for rehydration and reproducibility - from Kazuto Nishimori https://kazuto-nishimori.github.io/
dorianTweetId <- select(dorian,("status_id"))
write.csv(dorianTweetId,file="dorianTweetID.csv")
