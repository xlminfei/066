make_unequal_fixture_v32 <- function(destination, n_species=12L) {
  if(n_species!=12L)stop("This fixed synthetic fixture has 12 species")
  p<-data.frame(Species=sprintf("synthetic_%02d",1:12),
    Site3=c(rep("C",4),rep("R",4),"MISSING",rep("Q",3)),
    Site20=c(rep("K",6),rep("V",6)),
    Site117=c(rep("K",4),rep("S",6),"MISSING","G"),
    Site151="C",Site196=c(rep("C",4),rep("A",4),rep("G",4)),
    Site315=c(rep("K",6),rep("T",6)),stringsAsFactors=FALSE)
  rows<-list()
  for(i in 1:12) {
    n<-i+3L
    for(j in seq_len(n)) {
      type<-if(i==12L)"interval" else c("count","exact","interval")[(j-1L)%%3L+1L]
      total<-if(type=="count")as.integer(6+(i+j)%%7) else NA_integer_
      y<-if((i+j)%%4L==0L).85 else if((i+j)%%4L==1L).15 else if((i+j)%%4L==2L).65 else .35
      rows[[length(rows)+1L]]<-data.frame(RecordID=paste0("SYN_",i,"_",j),ExperimentID=paste0("SYNEXP_",i,"_",j),Species=p$Species[i],
        Type=type,Events=if(type=="count")as.integer(round(y*total)) else NA_integer_,Total=total,
        Exact=if(type=="exact")if(j%%7==0)1 else y else NA_real_,
        Lower=if(type=="interval").35 else NA_real_,Upper=if(type=="interval").65 else NA_real_,SourceID="SYNTHETIC_UNEQUAL_V32")
    }
  }
  obs<-do.call(rbind,rows)
  dir.create(file.path(destination,"input"),showWarnings=FALSE,recursive=TRUE)
  write_csv_atomic(p,file.path(destination,"input","sites.csv"));write_csv_atomic(obs,file.path(destination,"input","observations.csv"))
  prepare_state(file.path(destination,"input"))
}
