require(dplyr)
require(ggplot2)
require(lme4)
require(lmerTest)
require(mlogit)
require(stringdist)

theme_update(panel.grid.major = element_blank(), panel.grid.minor = element_blank(), panel.background = element_rect(colour = "black"),
             axis.text=element_text(size=20, colour = "black"), axis.title=element_text(size=18, face = "bold"), axis.title.x = element_text(vjust = 0),
             legend.title = element_text(size = 24, face = "bold"), legend.text = element_text(size = 20), plot.title = element_text(size = 26, face = "bold", vjust = 1))

setwd("~/Me/Psychology/Projects/choicesets/with_sam")


## Setup

getIndex = function(x, list) {
  y = numeric(length(x))
  for (j in 1:length(x)) {
    if (any(list %in% x[j])) {
      y[j] = which(list %in% x[j])
    } else {
      y[j] = NA
    }
  }
  return(y)
}

as.string.vector = function(x) {
  temp = strsplit(substr(x,2,nchar(x)-1), split=",")[[1]]
  return(substr(temp, 2, nchar(temp) - 1))
}

as.numeric.vector = function(x) {
  return(as.numeric(strsplit(substr(x,2,nchar(x)-1), split=",")[[1]]))
}

# Do logit
runLogit = function(df) {
  df$Choice = as.logical(df$Choice)
  df$OptionID = factor(df$OptionID)
  df = df %>% mutate(Trial_unique = paste(Subj, Trial, sep="_"))
  df$Trial = factor(df$Trial)
  df$Trial_unique = factor(df$Trial_unique)
  df$Subj = factor(df$Subj)
  df.m = mlogit.data(df, choice = "Choice", shape = "long", id.var = "Subj", alt.var = "OptionID", chid.var = "Trial_unique")
  
  m = mlogit(Choice ~ MFcent + MBcent + Int | -1, df.m, panel = T,
             rpar = c(MFcent = "n", MBcent = "n", Int = 'n'), correlation = F, halton = NA, R = 1000, tol = .001)
  return(m)
}

se = function(x) {return(sd(x) / sqrt(length(x)))}
dodge <- position_dodge(width=0.9)

numWords = 14;
numQuestions = 9; # including memory
pointsPerCent = 10;
pointsPerWord = 10; # for memory condition
path = 'data/cs_wg_v6/real1/'

# Load data
df.demo = read.csv(paste0(path, 'demo.csv'), stringsAsFactors = F) %>% arrange(subject) %>% mutate(total_time_real = total_time / 60000)
df.words.raw = read.csv(paste0(path, 'words.csv'), stringsAsFactors = F) %>% arrange(subject, word_ind)
df.s1.raw = read.csv(paste0(path, 's1.csv'), stringsAsFactors = F) %>% arrange(subject)
df.s2.raw = read.csv(paste0(path, 's2.csv'), stringsAsFactors = F) %>% arrange(subject, question_order)

subjlist = df.demo$subject


## Fix DFs

# drop anyone who didn't finish
df.s1 = df.s1.raw %>% filter(subject %in% subjlist) %>% mutate(correct_word = ain(toupper(resp), word, maxDist = 2))
df.s2 = df.s2.raw %>% filter(subject %in% subjlist)
df.words = df.words.raw %>% mutate(doubled = ifelse(is.na(lead(word)), FALSE, word == lead(word) & subject == lead(subject))) %>%
  filter(doubled == FALSE & subject %in% subjlist) %>%
  mutate(high_exp = exposures > 8, numChosen = 0)

# get pctCorrects
df.s1.subj = df.s1 %>% group_by(subject) %>% summarize(pctCorrect_words = mean(correct_word), pctCorrect_choice = mean(choice), numTrials = n())

# Mutate df.s2
df.s2$choice = toupper(df.s2$choice)
df.s2$scratch = gsub("[.]", ",", toupper(as.character(df.s2$scratch)))
df.s2$all_values = as.character(df.s2$all_values)

df.s2$rank_value = NULL
df.s2$num_ties = NULL
for (i in 1:nrow(df.s2)) {
  subj.name = df.s2$subject[i]
  wordlist = (df.words %>% filter(subject == subj.name))$word
  c = df.s2$choice[i]
  creal = wordlist[amatch(c, wordlist, maxDist = 2)]
  cind = getIndex(creal, wordlist)
  
  all_vals = as.numeric.vector(df.s2$all_values[i])
  #all_vals = rewards_te[qvec[df.s2$question_ind[i] + 1], ] * mult[df.s2$question_ind[i] + 1]
  #df.s2$all_values[i] = paste0('[', toString(all_vals), ']')
  
  all_vals_rank = rank(all_vals, ties.method = 'max')
  s2_val = ifelse(is.na(cind), NA, all_vals[cind])
  word_rows = subj.name == df.words$subject & creal == df.words$word
  
  df.s2$choice_real[i] = creal
  df.s2$choice_real_ind[i] = cind
  df.s2$s2_value[i] = s2_val
  df.s2$rank_value[i] = ifelse(is.na(cind), NA, all_vals_rank[cind])
  df.s2$num_ties[i] = ifelse(is.na(cind), NA, sum(s2_val == all_vals))
  df.s2$s1_value[i] = ifelse(is.na(cind), NA, df.words$value[word_rows])
  df.s2$s1_exposures[i] = ifelse(is.na(cind), NA, df.words$exposures[word_rows])
  df.s2$s1_chosen[i] = ifelse(is.na(cind), NA, df.words$numChosen[word_rows])
  
  df.s2$numWords_s1val[i] = ifelse(is.na(cind), NA, ifelse(df.s2$s1_value[i] %in% c(0,10), 3, 2))
  
  #df.s2$comp_check_almost[i] = abs(as.numeric(df.s2$comp_check[i]) - correct_comp[df.s2$question_ind[i] + 1]) <= mult[df.s2$question_ind[i] + 1]
}

df.s2 = df.s2 %>% mutate(s2_subj_ind = as.numeric(as.factor(subject)), # don't use that ind for anything serious
                         doubled = ifelse(is.na(choice_real_ind), NA, ifelse(is.na(lead(choice_real_ind)), F, choice_real_ind == lead(choice_real_ind)) |
                                                  ifelse(is.na(lag(choice_real_ind)), F, choice_real_ind == lag(choice_real_ind))),
                         bonus_value = ifelse(is.na(choice_real_ind), 0, ifelse(doubled, 0, s2_value)),
                         high_val = s1_exposures > 8)

df.mem = df.s2 %>% filter(question == 'Memory')

df.s2.subj = df.s2 %>% filter(subject %in% df.demo$subject) %>%
  group_by(subject) %>%
  summarize(s2_bonus = sum(bonus_value), rt = mean(rt) / 1000,
            comp_check_pass = mean(comp_check_pass),
            #comp_check_almost = mean(comp_check_almost, na.rm = T),
            comp_check_rt = mean(comp_check_rt) / 1000,
            numNAs = sum(is.na(choice_real)),
            numRepeats = sum(choice_real == lag(choice_real), na.rm = T))


## Compute recalled
recalled = matrix(F, nrow = nrow(df.mem), ncol = numWords)
recalled_ever = matrix(F, nrow = nrow(df.mem), ncol = numWords)
df.words$recall = NULL
df.words$recall.ever = NULL
df.words$order = NULL

for (i in 1:nrow(df.mem)) {
  subj.name = df.mem$subject[i]
  df.words.temp = df.words %>% filter(subject == subj.name)
  df.s2.temp = df.s2 %>% filter(subject == subj.name)
  
  words_temp = trimws(as.string.vector(df.mem$choice[i]))
  val_temp = as.numeric(trimws(as.string.vector(df.mem$scratch[i])))
  
  wordlist = df.words.temp$word
  
  if (length(wordlist) == numWords) {
    for (j in 1:numWords) {
      which_word = amatch(wordlist[j], words_temp, maxDist = 2, nomatch = 0)
      recalled[i,j] = which_word > 0
      
      if (recalled[i,j]) {
        true_val = df.words.temp$value[df.words.temp$word_ind  == (j - 1)]
      }
      df.words$recall[df.words$subject == subj.name & df.words$word == wordlist[j]] = recalled[i,j]
      
      recalled_ever[i,j] = recalled[i,j] | any(na.omit(df.s2.temp$choice_real_ind) == j)
      df.words$recall.ever[df.words$subject == subj.name & df.words$word == wordlist[j]] = recalled_ever[i,j]
      
      df.words$order[df.words$subject == subj.name & df.words$word == wordlist[j]] = which_word
    }
  }
}

## Compute exclusion
# Exclude if any of these: cor in s1 < .75, comp_check_pass < .5, pctCorrect_words < .75, pctCorrect_pts < .75, numNAs > 3, numRepeats > 2, numRecalled < 5
include_rows = NULL
include_names = NULL

for (subj in 1:nrow(df.demo)) {
  subj.name = df.demo$subject[subj]
  df.s1.subj.temp = df.s1.subj %>% filter(subject == subj.name)
  df.s2.subj.temp = df.s2.subj %>% filter(subject == subj.name)

  if (df.s1.subj.temp$pctCorrect_words < .75 || df.s1.subj.temp$pctCorrect_choice < .75 || df.s2.subj.temp$comp_check_pass < .5 ||
      df.s2.subj.temp$numRepeats > 2 || sum(recalled[subj,]) < 5 || df.s1.subj.temp$numTrials != 112 || df.s2.subj.temp$numNAs > 4) {
    include_rows[subj] = FALSE
  } else {
    include_rows[subj] = TRUE
    include_names = c(include_names, subj.name)
  }
}

good_v6 = c(1,2,5,7,11,14,15,17,18,19,22,24,26,27,28,29,30,31,32,34,35,36,37,38,41,44,45,46,49,50,51,52,53,54,55,59,60,63,64,66,67,70,72,73,75,76,77,79,83,85,86,87,88,90,92,93,95,96,98,100,101,102,103,104,106,107)
include_names_good = include_names[good_v6]

## Check out data
nrecall = rowSums(recalled[include_rows,])
mean(nrecall)

df.words.coll = df.words %>% filter(subject %in% include_names) %>% group_by(high_val, subject) %>% summarize(recall = mean(recall, na.rm = T)) %>%
  group_by(high_val) %>% summarize(recall.mean = mean(recall, na.rm = T), recall.se = se(recall))
ggplot(df.words.coll, aes(x = high_val, y = recall.mean)) +
  geom_bar(stat = "identity", position = dodge) +
  geom_errorbar(aes(ymax = recall.mean + recall.se, ymin = recall.mean - recall.se), width = .5, position = dodge) +
  xlab('') + ylab('') + guides(fill = F)

# Test what affected recall
m.recall = glmer(recall ~ high_exp + (0 + high_exp | subject) + (1 | subject) + (1 | word),
                 data = df.words %>% filter(subject %in% include_names), family = binomial)
summary(m.recall)


## Check out df.s2 stats
hist(df.s2[df.s2$subject %in% include_names, ]$rank_value, breaks = 15, main = "S2 ranks of words chosen in S2", xlab = "S2 rank")
mean(df.s2[df.s2$subject %in% include_names, ]$rank_value, na.rm = T)

hist(df.s2[df.s2$subject %in% include_names, ]$s1_exposures, breaks = 15, main = "S1 values of words chosen in S2", xlab = "S1 value")
mean(df.s2[df.s2$subject %in% include_names, ]$s1_exposures, na.rm = T)

# Test order
histogram(~ order | value, df.words[df.words$subject %in% include_names & df.words$recall == T, ])
m.order = lmer(order ~ high_exp + (high_exp | subject) + (high_exp | word),
                 data = df.words[df.words$subject %in% include_names & df.words$recall == T, ])
summary(m.order)


## Prepare for mlogit
numRealQuestions = numQuestions - 1
df.logit = data.frame(Subj = NULL, Trial = NULL, OptionID = NULL, Choice = NULL, MFval = NULL, MBval = NULL, nExposures = NULL, Recalled = NULL, Question = NULL)

for (subj in 1:nrow(df.demo)) {
  subj.name = df.demo$subject[subj]
  recalled.temp = recalled_ever[subj, ]
  #recalled.temp = !logical(numWords)
  num.recalled.temp = sum(recalled.temp)
  
  df.words.temp = df.words %>% filter(subject == subj.name)
  df.s2.temp = df.s2 %>% filter(subject == subj.name) %>% arrange(question_order)
  
  nAnswered = sum(!is.na(df.s2.temp$choice_real_ind))
  
  if (nAnswered > 0 & subj.name %in% include_names & !(subj.name %in% include_names_good)) {
    Subj.col = rep(subj, num.recalled.temp * nAnswered)
    
    MFval.col = rep(df.words.temp$value[recalled.temp], nAnswered)
    MFhigh.col = rep(df.words.temp$high_exp[recalled.temp] * 1, nAnswered)
    Recalled.col = rep(df.words.temp$recall.ever[recalled.temp] * 1, nAnswered)
    numChosen.col = rep(df.words.temp$numChosen[recalled.temp], nAnswered)
    #OptionID.col = rep(which(recalled.temp), nAnswered)
    OptionID.col = rep(1:num.recalled.temp, nAnswered)
    Trial.col = rep(1:nAnswered, each = num.recalled.temp)
    Question.col = rep(df.s2.temp$question_ind[!is.na(df.s2.temp$choice_real_ind)], each = num.recalled.temp)
    
    temp.mbval = matrix(0, nrow = nAnswered, ncol = num.recalled.temp)
    temp.mbhigh = matrix(0, nrow = nAnswered, ncol = num.recalled.temp)
    temp.choice = matrix(0, nrow = nAnswered, ncol = num.recalled.temp)
    temp.choice2 = matrix(0, nrow = nAnswered, ncol = num.recalled.temp)
    ind = 1
    for (q in 1:numRealQuestions) {
      if (!is.na(df.s2.temp$choice_real_ind[q])) {
        all_vals = as.numeric.vector(df.s2.temp$all_values[q])
        mbvals = rank(all_vals, ties.method = 'max')
        #mbvals = all_vals
        temp.mbval[ind,] = mbvals[recalled.temp]
        temp.mbhigh[ind,] = mbvals[recalled.temp] > 7
        
        choice = logical(num.recalled.temp)
        choice[which(df.s2.temp$choice_real_ind[q] == which(recalled.temp))] = TRUE
        temp.choice[ind,] = choice
        
        choice2 = vector(mode = 'numeric', num.recalled.temp)
        #choice2[1] = which(df.s2.temp$choice_real_ind[q] == which(recalled.temp))
        choice2[1] = OptionID.col[1:num.recalled.temp][choice]
        temp.choice2[ind,] = choice2
        
        ind = ind + 1
      }
    }
    
    MBval.col = as.vector(t(temp.mbval))
    MBhigh.col = as.vector(t(temp.mbhigh))
    Choice.col = as.vector(t(temp.choice))
    Choice2.col = as.vector(t(temp.choice2))
    
    df.logit = rbind(df.logit,
                     data.frame(Subj = Subj.col, Trial = Trial.col, OptionID = OptionID.col, Choice = Choice.col,
                                MFhigh = MFhigh.col, MBval = MBval.col, MBhigh = MBhigh.col, Choice2 = Choice2.col,
                                Recall = Recalled.col, nChosen = numChosen.col, Question = Question.col))

  }
}

df.logit = df.logit %>% mutate(MFcent = MFhigh - mean(MFhigh), MBcent = MBval - mean(MBval), Int = MFcent * MBcent)

m.real = runLogit(df.logit)
summary(m.real)


## Graph
df.sum = df.logit %>% group_by(MFhigh,MBhigh) %>% summarize(Choice.mean = mean(Choice)) #%>% mutate(Choice.mean = Choice.mean * ifelse(MFval %in% c(0,10), 2/3, 1))

ggplot(data = df.sum, aes(x = MBhigh, y = Choice.mean, group = MFhigh, colour = MFhigh)) +
  geom_point(aes(size = 2)) + geom_line()


## Get bonuses
nrecall_bonus = rowSums(recalled)
df.s2.subj = df.s2.subj %>% mutate(mem_bonus = nrecall_bonus[df.mem$subject == subject] * pointsPerWord)
df.demo = df.demo %>% mutate(s2_bonus = I(df.s2.subj$s2_bonus), mem_bonus = I(df.s2.subj$mem_bonus),
                             bonus = round((s1_bonus + s2_bonus + mem_bonus) / (pointsPerCent * 100), 2))
write.table(df.demo %>% filter(id >= 150) %>% select(WorkerID = subject, Bonus = bonus),
            paste0(path, 'Bonuses - cs_wg_v6_pilot2.csv'), row.names = FALSE, col.names = FALSE, sep = ",")

save.image(paste0(path, 'analysis.rdata'))


## Save for modeling

rewards_tr = matrix(0, nrow = sum(include_rows), ncol = numWords)
ind = 1
for (subj in 1:nrow(df.demo)) {
  subj.name = df.demo$subject[subj]
  
  if (subj.name %in% include_names) {
    df.words.temp = df.words %>% filter(subject == subj.name)
    
    for (word in 1:numWords) {
      rewards_tr[ind, word] = df.words.temp$exposures[word]
    }
    ind = ind + 1
  }
}

write.csv(rewards_tr, paste0(path, 'rewards_tr.csv'), row.names = F)
write.csv(recalled_ever[include_rows, ] * 1, paste0(path, 'recalled.csv'), row.names = F)

df.modeling = df.s2 %>% filter(subject %in% include_names & !is.na(choice_real_ind)) %>%
  mutate(all_values_nocomma = gsub(",", " ", all_values)) %>% 
  select(s2_subj_ind, choice_real_ind, all_values_nocomma)
write.table(df.modeling, paste0(path, 'choices.csv'), row.names = F, col.names = F, sep=",");








## Bootstrapping power analysis
nBS = 50
nSubj = 200
subjlist.logit = unique(df.logit$Subj)

ps = numeric(nBS)
for (bs in 1:nBS) {
  df.bs = data.frame(Subj = NULL, Trial = NULL, OptionID = NULL, Choice = NULL, MFval = NULL, MBval = NULL, nExposures = NULL, Recalled = NULL)
  
  set.seed(Sys.time())
  for (i in 1:nSubj) {
    # choose random
    subj = sample(subjlist.logit, 1)
    df.bs = rbind(df.bs, df.logit %>% filter(Subj == subj) %>% mutate(Subj = i))
  }
  
  df.bs = df.bs %>% mutate(MFcent = MFval - mean(MFval), MBcent = MBval - mean(MBval), Int = MFcent * MBcent)
  m.bs = runLogit(df.bs)
  ps[bs] = summary(m.bs)$CoefTable[3,4]
}

mean(ps < .1)





## Simulations
df.sim.cs = read.csv('simulations/results/wg_v3/cs-mf-mb.csv') %>% mutate(MBval = ifelse(MBval > 7, 1, 0), MFcent = MFval - mean(MFval), MBcent = MBval - mean(MBval), Int = MFcent * MBcent)
m.sim.cs = runLogit(df.sim.cs)
summary(m.sim.cs)

m.sim.cs = runLogit_b(df.sim.cs)
summary(m.sim.cs)
estbetas = apply(m.sim.cs$betadraw, c(1,2), mean)
hist(estbetas[,3])
t.test(estbetas[,3])

df.sim.null = read.csv('simulations/results/wg_v3/mixture-mf-mb.csv') %>% mutate(MFcent = MFval - mean(MFval), MBcent = MBval - mean(MBval), Int = MFcent * MBcent)
m.sim.null = runLogit(df.sim.null)
summary(m.sim.null)

# Graph
df.rank.sim.cs = read.csv('simulations/results/wg_v3/cs-mf-mb-s2.csv')
nrows = nrow(df.rank.sim.cs)
df.rank.sim.cs = df.rank.sim.cs %>%
  mutate(Stage1_value = factor(s1_value > 5, c(F,T), c('Low', 'High')), Stage2_value = factor(rank_value > 7, c(F,T), c('Low', 'High'))) %>%
  group_by(Stage2_value, Stage1_value) %>%
  summarize(numChosen_S2 = n(), prob_rank = numChosen_S2 / nrows) %>%
  mutate(log_prob_rank = log(prob_rank))

base = ggplot(data = df.rank.sim.cs, aes(x = Stage2_value, y = prob_rank, group = Stage1_value, colour = Stage1_value)) +
  geom_point(aes(size = 2))
base + guides(size  = F) + ylab('') +
  xlab('') + geom_smooth(method='lm',formula=y~x)