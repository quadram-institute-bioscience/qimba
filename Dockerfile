FROM qiime2/core:2019.4

COPY . /qimba
ENV PATH="/qimba:/qimba/tools/:${PATH}"  
