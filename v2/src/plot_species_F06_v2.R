root <- normalizePath(Sys.getenv("V2_ROOT", getwd()), winslash = "/", mustWork = TRUE)
out <- file.path(root,"postprocess_20260919")
fig <- file.path(out,"figures")
dir.create(fig,recursive=TRUE,showWarnings=FALSE)
suppressPackageStartupMessages({library(ggplot2);library(grid);library(gridExtra)})
full <- read.csv(file.path(root,"results","full_panel_predictions_v2.csv"),stringsAsFactors=FALSE,check.names=FALSE)
models <- c("Null","Site315","M1","M2","M3")
routes <- c(binary="High/Low",joint_bb="Joint beta-binomial",schemeA_tobit="Scheme A report-level")
stopifnot(nrow(full)==365L*5L*3L, all(is.finite(full$Point)))
full$Species <- as.character(full$Species)
order_species <- full$Species[full$Route=="binary" & full$Model=="M1"]
order_species <- order_species[order(order_species)]
pages <- split(order_species, ceiling(seq_along(order_species)/42L))
make_panel <- function(z, model, route, names_page, show_y) {
  z <- z[match(names_page,z$Species),,drop=FALSE]
  # Keep row labels and plotted rows in the same order. scale_y_reverse()
  # puts the first species at the top without reversing their pairing.
  z$y <- seq_along(names_page)
  z$fill <- ifelse(z$Status=="supported","#FFFFFF","#FDE0DD")
  z$line <- ifelse(z$Status=="supported","#0072B2","#D7301F")
  p <- ggplot(z,aes(y=y,x=Point))
  if(route!="binary") {
    p <- p + geom_segment(aes(x=PI_lower,xend=PI_upper,y=y,yend=y),
                          color="#D55E00",linewidth=1.0)
  }
  p <- p + geom_segment(aes(x=CrI_lower,xend=CrI_upper,y=y,yend=y),
                        color="#0072B2",linewidth=1.2) +
    geom_point(aes(fill=fill,color=line),shape=21,size=1.8,stroke=.55) +
    scale_x_continuous(limits=c(0,1),breaks=c(0,.5,1),labels=c("0",".5","1"),
                       expand=c(.01,.01)) +
    scale_y_reverse(breaks=seq_along(names_page),
                       labels=if(show_y) names_page else rep("",length(names_page)),
                       expand=expansion(add=.6)) +
    scale_fill_identity() + scale_color_identity() +
    labs(title=model,x=if(route=="binary")"Pr(HIGH)" else "Ratio",y=NULL) +
    theme_minimal(base_size=8.5) +
    theme(plot.title=element_text(size=10,face="bold",hjust=.5),
          panel.grid.major.y=element_blank(),panel.grid.minor=element_blank(),
          axis.text.y=if(show_y) element_text(size=7,face="italic") else element_blank(),
          axis.ticks.y=if(show_y) element_line() else element_blank(),
          axis.title.x=element_text(size=8),axis.text.x=element_text(size=7),
          plot.margin=margin(3,3,3,3))
  p
}
caption <- function(route) {
  if(route=="binary")
    "Point: Pr(High); blue line: 95% posterior CrI. Open/red points mark extrapolation or missing input."
  else
    "Point: expected exact-report ratio; blue: 95% posterior CrI; orange: 95% predictive PI. Open/red points mark extrapolation or missing input."
}
for(route in names(routes)) {
  pdf_path <- file.path(fig,paste0("F06_full_species_predictions_",route,"_corrected.pdf"))
  pdf(pdf_path,width=285/25.4,height=255/25.4,onefile=TRUE)
  for(i in seq_along(pages)) {
    names_page <- pages[[i]]
    rows <- full[full$Route==route & full$Species %in% names_page,,drop=FALSE]
    plots <- lapply(seq_along(models),function(j)
      make_panel(rows[rows$Model==models[[j]],,drop=FALSE],models[[j]],route,names_page,j==1L))
    top <- textGrob(paste0(routes[[route]],": full-panel predictions | ",i,"/",length(pages)),
                    gp=gpar(fontsize=15,fontface="bold",col="#203040"),x=0.02,hjust=0)
    sub <- textGrob("Full-data fit; not held-out validation. The 365 panel predictions are not 365 new experiments.",
                    gp=gpar(fontsize=9,col="#607080"),x=0.02,hjust=0)
    bot <- textGrob(caption(route),gp=gpar(fontsize=8,col="#607080"),x=0.02,hjust=0)
    g <- arrangeGrob(grobs=plots,ncol=5,top=textGrob("",gp=gpar(fontsize=1)),
                     bottom=bot)
    page <- arrangeGrob(grobs=list(top, sub, g),
                        heights=unit.c(unit(0.25,"in"), unit(0.18,"in"), unit(1,"null")),
                        ncol=1)
    if (i > 1L) grid.newpage()
    grid.draw(page)
    source <- rows[rows$Species %in% names_page,
                   c("Species","Model","Point","CrI_lower","CrI_upper",
                     "PI_lower","PI_upper","Status"),drop=FALSE]
    source$Species <- factor(source$Species, levels=names_page)
    source$Model <- factor(source$Model, levels=models)
    source <- source[order(source$Species,source$Model),,drop=FALSE]
    source$Species <- as.character(source$Species)
    source$Model <- as.character(source$Model)
    write.csv(source,file.path(fig,paste0("F06_species_",route,"_corrected_p",sprintf("%02d",i),"_source.csv")),row.names=FALSE)
    writeLines(c("# F06 page caption","","",caption(route)),
               file.path(fig,paste0("F06_species_",route,"_corrected_p",sprintf("%02d",i),"_caption_zh.md")),
               useBytes=TRUE)
    png_path <- file.path(fig,paste0("F06_species_",route,"_corrected_p",sprintf("%02d",i),".png"))
    png(png_path,width=2850,height=2550,res=300)
    grid.draw(page); dev.off()
  }
  dev.off()
}
cat("F06_V2_COMPLETE pages=",length(pages)," routes=",length(routes),"\n",sep="")
