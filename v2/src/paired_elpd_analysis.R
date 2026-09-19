root <- normalizePath(Sys.getenv("V2_ROOT", getwd()), winslash = "/", mustWork = TRUE)
out <- file.path(root,"postprocess_20260919")
fig <- file.path(out,"figures")
dir.create(fig,recursive=TRUE,showWarnings=FALSE)
suppressPackageStartupMessages({library(ggplot2);library(scales)})
d <- read.csv(file.path(root,"results","cv_record_scores_v2.csv"),stringsAsFactors=FALSE)
models <- c("Site315","M1","M2","M3")
refs <- c("Null","Site315")
cmp <- list()
for(route in unique(d$Route)) for(design in unique(d$Design)) {
  for(m in models) for(ref in refs) {
    if(m==ref) next
    a <- d[d$Route==route & d$Design==design & d$Model==m, c("RecordID","Species","Score")]
    b <- d[d$Route==route & d$Design==design & d$Model==ref, c("RecordID","Species","Score")]
    names(a)[3] <- "Score_model"; names(b)[3] <- "Score_reference"
    if(!nrow(a) || !nrow(b)) next
    z <- merge(a,b,by=c("RecordID","Species"),all=FALSE)
    if(!nrow(z)) next
    by_species <- aggregate(cbind(Score_model,Score_reference)~Species,z,sum)
    by_species$Difference <- by_species$Score_model-by_species$Score_reference
    ns <- nrow(by_species); nr <- nrow(z)
    se <- if(ns>1) sqrt(ns*stats::var(by_species$Difference)) else NA_real_
    delta <- sum(by_species$Difference)
    zz <- if(is.finite(se) && se>0) delta/se else NA_real_
    pp <- if(is.finite(zz)) 2*stats::pnorm(-abs(zz)) else NA_real_
    cmp[[length(cmp)+1L]] <- data.frame(Route=route,Design=design,Model=m,
      Reference=ref,Records=nr,Species=ns,ELPD_difference=delta,
      Paired_SE_species=se,CI95_lower=delta-1.96*se,CI95_upper=delta+1.96*se,
      z_normal_approx=zz,p_value_normal_approx=pp,stringsAsFactors=FALSE)
  }
}
res <- do.call(rbind,cmp)
res$p_value_BH_all <- stats::p.adjust(res$p_value_normal_approx,method="BH")
res$RouteLabel <- c(binary="High/Low",joint_bb="Joint beta-binomial",
                    schemeA_tobit="Scheme A")[res$Route]
res$DesignLabel <- ifelse(res$Design=="species5","Five-fold","Ten-fold")
write.csv(res,file.path(out,"paired_elpd_comparisons.csv"),row.names=FALSE)
res$Label <- ifelse(is.finite(res$p_value_BH_all),sprintf("BH p=%.3f",res$p_value_BH_all),"")
res$Model <- factor(res$Model,levels=c("Site315","M1","M2","M3"))
res$Reference <- factor(res$Reference,levels=c("Null","Site315"))
p <- ggplot(res,aes(Model,ELPD_difference,color=Reference))+
  geom_hline(yintercept=0,linetype=2,color="grey55")+
  geom_errorbar(aes(ymin=CI95_lower,ymax=CI95_upper),position=position_dodge(width=.55),width=.12)+
  geom_point(position=position_dodge(width=.55),size=1.8)+
  facet_grid(RouteLabel~DesignLabel,scales="free_y")+
  scale_color_manual(values=c(Null="#0072B2",Site315="#D55E00"))+
  labs(title="Paired held-out ELPD differences",
       subtitle="Species-clustered paired SE; CI and p values use a normal approximation",
       x=NULL,y="ELPD difference (model - reference)",color="Reference")+
  theme_minimal(base_size=9)+theme(legend.position="bottom")
ggsave(file.path(fig,"F08_paired_ELPD_comparisons.pdf"),p,width=10,height=8,units="in",device="pdf")
ggsave(file.path(fig,"F08_paired_ELPD_comparisons.png"),p,width=10,height=8,units="in",dpi=300)
fmt <- function(x) ifelse(is.na(x),"NA",formatC(x,format="f",digits=3))
tab <- res[,c("RouteLabel","DesignLabel","Model","Reference","Species","Records",
              "ELPD_difference","Paired_SE_species","CI95_lower","CI95_upper",
              "z_normal_approx","p_value_normal_approx","p_value_BH_all")]
names(tab) <- c("Route","Design","Model","Reference","Species","Records",
                "ELPD_difference","Paired_SE_species","CI95_lower","CI95_upper",
                "z_normal_approx","p_value_normal_approx","p_value_BH_all")
lines <- c("# ELPD 配对标准误和近似检验",
  "",
  "这里把同一折分、同一路线、同一物种的多条留出记录先求和，再以物种作为配对单位比较模型与 Null 或 Site315。paired SE 按物种差值的样本方差计算：sqrt(n_species × var(difference))。p 值和 95% 区间使用正态近似；这是模型比较的辅助推断，不是对生物学效应的显著性检验。表中同时给出 Benjamini-Hochberg 全表校正 p 值，不能替代预先声明的多重比较方案。",
  "",
  "- [完整比较表](paired_elpd_comparisons.csv)",
  "- [配对差值图](figures/F08_paired_ELPD_comparisons.pdf)",
  "",
  "## 结果表",
  "",
  paste0("| ",paste(names(tab),collapse=" | ")," |"),
  paste0("| ",paste(rep("---",ncol(tab)),collapse=" | ")," |"),
  apply(tab,1,function(x)paste0("| ",paste(x,collapse=" | ")," |")))
writeLines(lines,file.path(out,"ELPD_PAIRED_SE_ANALYSIS_zh.md"),useBytes=TRUE)
cat("PAIRED_ELPD_COMPLETE rows=",nrow(res),"\n",sep="")
