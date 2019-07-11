FROM debian:buster-slim

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update --fix-missing && \
    apt-get install -y wget bzip2 ca-certificates libglib2.0-0 libxext6 libsm6 libxrender1 git mercurial subversion && \
    apt-get clean

RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda2-4.6.14-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate base" >> ~/.bashrc && \
    find /opt/conda/ -follow -type f -name '*.a' -delete && \
    find /opt/conda/ -follow -type f -name '*.js.map' -delete && \
    /opt/conda/bin/conda clean -afy
#    conda install  -c bioconda -y perl-app-cpanminus
#RUN cpanm SUPER && cpanm FASTX::Reader \
#	&& cpanm IPC::RunExternal && cpanm --force Archive::Zip && cpanm --force Archive::Zip::Member && cpanm Text::CSV && cpanm Proch::N50; echo 1

COPY . /qimba
ENV PATH="/opt/conda/envs/qiime2-2019.4/bin/:/opt/conda/bin/:/usearch/:/qimba:/qimba/tools/:${PATH}"
ENV PERL5LIB="/qimba/lib"
RUN chmod 555 /qimba/qimba.pl

RUN conda env create -n qiime2-2019.4 --file /qimba/bin/qiime2.yml

#CMD [ "/bin/bash" ]
WORKDIR /data
#ENTRYPOINT [ "/qimba/qimba.pl", "--docker" ]
