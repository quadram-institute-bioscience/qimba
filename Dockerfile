FROM qiime2/core:2019.4
RUN apt update && apt install -y build-essential
RUN conda install -n qiime2-2019.4 -c bioconda -y perl-app-cpanminus 
#RUN cpanm SUPER && cpanm FASTX::Reader \
#	&& cpanm IPC::RunExternal && cpanm --force Archive::Zip && cpanm --force Archive::Zip::Member && cpanm Text::CSV && cpanm Proch::N50; echo 1
COPY . /qimba
ENV PATH="/usearch/:/qimba:/qimba/tools/:${PATH}" 
ENV PERL5LIB="/qimba/lib"
RUN chmod 555 /qimba/qimba.pl
