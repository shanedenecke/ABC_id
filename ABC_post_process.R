#!/usr/bin/env Rscript
shhh <- suppressPackageStartupMessages
shhh(library(data.table))
shhh(library(tidyverse))
shhh(library(gplots))
shhh(library(ggsci))
shhh(library(agricolae))


############## Directories
setwd('/mnt/disk/shane/Transporter_ID/Arthropod_ABC_pipeline')
#setwd('C:/Users/shane/Dropbox/writing/manuscripts/Under_Review/ABC_id/Revision_Data/')
dir.create('./Final_outputs',showWarnings = F)
dir.create('./Final_outputs/ABC_dicts',showWarnings = F)
dir.create('./Final_outputs/ABC_proteomes',showWarnings = F)
dir.create('./Final_outputs/combined_files',showWarnings = F)
dir.create('./Final_outputs/Figures_Tables',showWarnings = F)

############## Functions
shane.transpose=function(dt,newcol){
  new.rows=colnames(dt)[2:length(colnames(dt))]
  a=transpose(dt)
  colnames(a)=as.character(a[1,])
  a=a[-1,]
  b=mutate(a,newcol=new.rows) %>% select(newcol,everything()) %>% data.table()
  return(b)
}

formatter <- function(...){
  function(x) format(round(x, 0), ...)
}


############## Import common datasets
meta=fread('./GENERAL_REFERENCE/keys/Arthropod_species_metadata.tsv')
benchmark.raw=fread('./GENERAL_REFERENCE/keys/ABC_benchmark_counts.csv') %>% select(-Order) 
busco.unfiltered=fread('./BUSCO/BUSCO_final_summary_unfiltered.tsv') %>% rename(abbreviation=Species)
busco.filtered=fread('./BUSCO/BUSCO_final_summary.tsv') %>% rename(abbreviation=Species)

############## Extract Final proteomes and dictionaries from each ABC species
for (i in list.files('./ABC_search',full.names = T)){
  base=basename(i)
  file.copy(paste0(i,'/','Final_ABCs.faa'),paste0('./Final_outputs/ABC_proteomes/',base,'_Final_ABC_proteins.faa'),overwrite = T)
  file.copy(paste0(i,'/','Final_ABC_table.tsv'),paste0('./Final_outputs/ABC_dicts/',base,'_Final_ABC_table.tsv'),overwrite = T)
}
system('cp ./GENERAL_REFERENCE/Model_ABC_sets/ABC_proteins/*.faa ./Final_outputs/ABC_proteomes/')
system('cp ./GENERAL_REFERENCE/Model_ABC_sets/ABC_final_tables/*.tsv ./Final_outputs/ABC_dicts/')

############## combine all figures and tables to generate full_dictionary and full ABC_proteome
system('cat ./Final_outputs/ABC_proteomes/* > ./Final_outputs/combined_files/All_ABCs.faa')
all.tables=lapply(as.list(list.files('./Final_outputs/ABC_dicts/',full.names = T)),fread)
final.table=rbindlist(all.tables,fill=T)
final.table=final.table[fam!='ABC_Unsorted']
fwrite(final.table,'./Final_outputs/combined_files/Final_full_dictionary.tsv',sep='\t')


############## Make counts tables 
count.raw=final.table %>% group_by(fam,abbreviation) %>% summarize(count=n()) %>% data.table() 
count.wide=count.raw %>% dcast(fam~abbreviation,value.var='count')
count.long=count.raw %>% dcast(abbreviation~fam,value.var='count') 
sums=select(count.long,-abbreviation) %>% rowSums(na.rm=T)
count.long=count.long %>% 
  #mutate(ABC_total=ABCA+ABCBF+ABCH+ABCC+ABCD+ABCE+ABCF+ABCG+ABCH+ABC_Unsorted) %>% 
  #mutate(ABC_total=sum(ABCA,ABCBF,ABCH,ABCC,ABCD,ABCE,ABCF,ABCG,ABCH,ABC_Unsorted,na.rm = T)) %>% 
  mutate(ABC_total=sums) %>%
  merge(meta,by='abbreviation',all=T) %>% 
  merge(busco.filtered,by='abbreviation') %>% 
  data.table()

count.long.busco.un=merge(meta,busco.unfiltered,by='abbreviation') %>% merge(select(count.long,ABCA:ABC_total,abbreviation),by='abbreviation',all=T)

fwrite(count.wide,'./Final_outputs/combined_files/Full_counts_wide.tsv',sep='\t')
fwrite(count.long,'./Final_outputs/combined_files/Full_counts_long.tsv',sep='\t')
fwrite(count.long.busco.un,'./Final_outputs/combined_files/Full_counts_long_BUSCO_unfiltered.tsv',sep='\t')


############## Benchmarking against known datasets 
merged.benchmark=select(count.long,Species_name,ABC_total) %>% merge(benchmark.raw,by='Species_name') %>% rename(ABC_This_Study=ABC_total)
merged.benchmark$Difference=merged.benchmark$ABC_This_Study-merged.benchmark$Lit_ABC_count
merged.benchmark$Percent_Difference=(merged.benchmark$Difference/merged.benchmark$ABC_This_Study)*100
merged.benchmark$Species_name=gsub('_',' ',merged.benchmark$Species_name)

############## Plot benchmark data
gp=ggplot(merged.benchmark,aes(x=Species_name,y=Percent_Difference))
gp=gp+geom_bar(stat='identity')
gp=gp+geom_hline(yintercept=0,linetype=1,size=2,color='red')
gp=gp+scale_y_continuous(breaks=seq(-50,50,by=10),limits=c(-25,25))
gp=gp+labs(x='\nSpecies Name',y='Percent Difference\n') 
gp=gp+geom_hline(yintercept=10,linetype='dashed')
gp=gp+geom_hline(yintercept=-10,linetype='dashed')
gp=gp+theme_bw()
gp=gp+theme(text=element_text(face="bold",family="serif"),panel.grid=element_blank(),
            axis.ticks.x=element_line(),panel.border=element_rect(colour="black",fill=NA),
            axis.title=element_text(size=24),
            axis.text.x=element_text(angle=30,hjust=1,size=16,face='bold.italic'),axis.text.y=element_text(size=12),
            legend.position = 'none',plot.title = element_text(hjust = 0.5),
            plot.margin=margin(t = 0, r = 2, b = 0, l = 2, unit = "cm"))

#print(gp)
ggsave(plot=gp,filename='./Final_outputs/Figures_Tables/FigureS2_Benchmark_graph.pdf',width=16,height=8)



############## Perform kruskal on groups and looks at plots
iter.i=select(count.long,ABCA:ABCH) %>% colnames()
iter.j='Taxonomic_Classification'
kruskal.l=list()

for(i in iter.i){
  for(j in iter.j){
    
    #### Filter Data for those groups which have over 5 individuals
    good=names(table(count.long[[j]]))[table(count.long[[j]])>5]
    sub=count.long[count.long[[j]] %in% good]
  
    kruskal.model=kruskal(sub[[i]],sub[[j]],p.adj='bonferroni')
    kruskal.summary=kruskal.model$groups %>% mutate(Taxonomic_Classification=rownames(.)) %>% 
      select(-`sub[[i]]`) %>% data.table() %>% mutate(p.value=kruskal.model$statistics$p.chisq,ABC_Family=i)
    means=kruskal.model$means %>% mutate(Taxonomic_Classification=rownames(.)) %>% select(Q75,Taxonomic_Classification)
    kruskal.summary=merge(kruskal.summary,means) %>% rename(statistics_groups=groups)
    kruskal.l[[paste(i,j,sep='_')]]=kruskal.summary
     }
}

kruskal.all=rbindlist(kruskal.l) 
kruskal.all$ABC_Family=gsub('ABC','ABC-',kruskal.all$ABC_Family)
kruskal.filter=kruskal.all %>% arrange() %>% data.table()
fwrite(kruskal.filter,'./Final_outputs/Figures_Tables/kruskal_table.csv')


############## Make boxplot for Variable Families
count.plot=select(count.long,abbreviation,Taxonomic_Classification,ABCA:ABCH) %>%
  filter(Taxonomic_Classification %in% c('Arachnida','Coleoptera',
                                         'Diptera','Hemiptera','Hymenoptera','Lepidoptera')) %>% 
  data.table() %>%
  melt(id.vars=c('abbreviation','Taxonomic_Classification'),measure.vars=patterns("ABC"), ###Melt data frame to have family and size be measurements
       variable.name='ABC_Family',value.name='Family_Size') %>%  ### remove taxonomic groups with fewer than 30 total events (fam x species). Generally under 5 species
  filter(ABC_Family %in% c('ABCBF','ABCC','ABCG','ABCH')) %>% ### only variable families
  data.table()
count.plot$ABC_Family=gsub('ABC','ABC-',count.plot$ABC_Family)


kruskal.sub=kruskal.all %>% filter(ABC_Family %in% c('ABC-BF','ABC-C','ABC-G','ABC-H')) %>% 
  filter(Taxonomic_Classification %in% c('Arachnida','Coleoptera','Diptera','Hemiptera','Hymenoptera','Lepidoptera')) 

gp=ggplot(count.plot,aes(x=Taxonomic_Classification,y=Family_Size,fill=Taxonomic_Classification)) 
gp=gp+geom_boxplot()
gp=gp+facet_wrap(vars(ABC_Family),nrow=2,scales='free')
gp=gp+labs(x='\nTaxonomic Group',y='Family Size\n')
gp=gp+scale_y_continuous(labels = formatter(nsmall = 0))
gp=gp+geom_text(data=kruskal.sub,aes(label=statistics_groups,x=Taxonomic_Classification,y=Q75),nudge_x = .1,vjust=-1)
gp=gp+theme_bw()
#gp=gp+scale_fill_manual(values=c('white','grey95','grey80','grey65','grey50','grey35'))
gp=gp+scale_fill_npg()
gp=gp+theme(text=element_text(face="bold",family="serif"),panel.grid=element_blank(),
            axis.ticks.x=element_line(),panel.border=element_rect(colour="black",fill=NA),
            strip.text=element_text(size=20),strip.background=element_rect("white"),
            axis.title=element_text(size=24),axis.text.y=element_text(size=14),
            axis.text.x=element_text(size=10),
            legend.position = 'none',
            plot.title = element_text(hjust = 0.5))

#print(gp)
ggsave(plot=gp,filename='./Final_outputs/Figures_Tables/Figure2_Taxonomy_Group_Comparison.pdf',width=12,height=8)


############## Make Boxplot graph for static families
count.plot=select(count.long,abbreviation,Taxonomic_Classification,ABCA:ABCH) %>%
  filter(Taxonomic_Classification %in% c('Arachnida','Coleoptera',
                                         'Diptera','Hemiptera','Hymenoptera','Lepidoptera')) %>% 
  data.table() %>%
  melt(id.vars=c('abbreviation','Taxonomic_Classification'),measure.vars=patterns("ABC"), ###Melt data frame to have family and size be measurements
       variable.name='ABC_Family',value.name='Family_Size') %>%  ### remove taxonomic groups with fewer than 30 total events (fam x species). Generally under 5 species
  filter(ABC_Family %in% c('ABCBH','ABCD','ABCE','ABCF')) %>% ### only variable families
  data.table()
count.plot$ABC_Family=gsub('ABC','ABC-',count.plot$ABC_Family)


kruskal.sub=kruskal.all %>% filter(ABC_Family %in% c('ABC-BH','ABC-D','ABC-E','ABC-F')) %>% 
  filter(Taxonomic_Classification %in% c('Arachnida','Coleoptera','Diptera','Hemiptera','Hymenoptera','Lepidoptera')) 

gp=ggplot(count.plot,aes(x=Taxonomic_Classification,y=Family_Size,fill=Taxonomic_Classification)) 
gp=gp+geom_boxplot()
gp=gp+facet_wrap(vars(ABC_Family),nrow=2,scales='free')
gp=gp+labs(x='\nTaxonomic Group',y='Family Size\n')
gp=gp+scale_y_continuous(labels = formatter(nsmall = 0))
gp=gp+geom_text(data=kruskal.sub,aes(label=statistics_groups,x=Taxonomic_Classification,y=Q75),nudge_x = .1,vjust=-1)
gp=gp+theme_bw()
#gp=gp+scale_fill_manual(values=c('white','grey95','grey80','grey65','grey50','grey35'))
gp=gp+scale_fill_npg()
gp=gp+theme(text=element_text(face="bold",family="serif"),panel.grid=element_blank(),
            axis.ticks.x=element_line(),panel.border=element_rect(colour="black",fill=NA),
            strip.text=element_text(size=20),strip.background=element_rect("white"),
            axis.title=element_text(size=24),axis.text.y=element_text(size=14),
            axis.text.x=element_text(size=10),
            legend.position = 'none',
            plot.title = element_text(hjust = 0.5))

#print(gp)
ggsave(plot=gp,filename='./Final_outputs/Figures_Tables/FigureS3_Non-variable_ABC_families.pdf',width=12,height=8)




#################### Histogram
gp=ggplot(count.long,aes(x=ABC_total))
gp=gp+geom_histogram(colour="black", fill="grey75",binwidth=5)
gp=gp+geom_density(alpha=.2, fill="#FF6666")
gp=gp+labs(x='\nTotal ABCs Identified in Species',y='Frequency\n')
gp=gp+theme_bw()
gp=gp+theme(text=element_text(face="bold",family="serif"),panel.grid=element_blank(),
            axis.ticks.x=element_line(),panel.border=element_rect(colour="black",fill=NA),
            axis.title=element_text(size=22),
            legend.position = 'none',plot.title = element_text(hjust = 0.5))
#print(gp)

ggsave(gp,file='./Final_outputs/Figures_Tables/FigureS1_ABC_histogram.pdf',device='pdf',width=20,height=10,units='cm')




# 
# ### Make individual boxplotsggplot
# gp=ggplot(data=sub,aes_string(x=j,y=i,fill=j))
# gp=gp+geom_boxplot(outlier.size=1)
# gp=gp+labs(x=paste0('\n',j),y=paste0(i,'\n'))
# gp=gp+geom_text(data=kruskal.summary,aes(label=statistics_groups,x=Taxonomic_Classification,y=Q75+2),nudge_x = .1)
# gp=gp+theme_bw()
# gp=gp+theme(text=element_text(face="bold",family="serif",size=16),panel.grid=element_blank(),
#             axis.ticks.x=element_line(),panel.border=element_rect(colour="black",fill=NA),
#             strip.text=element_text(size=20),strip.background=element_rect("white"),
#             axis.title=element_text(size=17),axis.text.x=element_text(size=16,angle=30,hjust=1),
#             legend.position = 'none',plot.title = element_text(hjust = 0.5))
# 
# #print(gp)
# ggsave(filename=paste0('./Final_outputs/Figures_Tables/kruskal_plots/',i,'_',j,'.png'),gp,device='png',height=7,width=7)




############## Produce heatmap 
# groups=c('Hymenoptera','Coleoptera','Hemiptera','Lepidoptera','Diptera','Arachnida','Crustacea')
# cols=c('firebrick2','blue4','magenta','green3','orange','mediumorchid3','gold3')
# 
# names(groups)=cols
# final.cols=c()
# for(i in 1:nrow(count.long)){
#   g=count.long$Taxonomic_Classification[i]
#   if(g %in% groups){final.cols[i]=names(groups[which(groups==g)])}else{final.cols[i]='black'}
# }
# 
# counts.matrix=count.long %>% 
#   select(matches("ABC"),-ABC_total) %>%
#   as.matrix() %>% t()
# colnames(counts.matrix)=count.long$Species_name

#pdf('./Final_outputs/Figures_Tables/ABC_heatmap.pdf',width=20,height=10)
#hm=heatmap.2(counts.matrix,Rowv=F,Colv=T,scale="row",col=colorpanel(75,'blue','grey','red'),
#             dendrogram = 'column',tracecol=NA,
#             colCol = final.cols,margins = c(10,8),cexRow=1.5,
#             density.info = 'density',denscol='black')
#dev.off()


