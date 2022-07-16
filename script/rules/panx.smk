# This snakemake workflow contains recipes to analyze the panx dataset with pangraph,
# and benchmark pangraph performances on real data.

import glob

PX_config = config["panx"]
# list of different species
PX_species = PX_config["species"]
# kernel options
PX_ker_opt = PX_config["kernel-options"]
# different kernel names
PX_ker_names = list(PX_ker_opt.keys())


def acc_nums(fld):
    files = glob.glob(fld + "/*.gbk")
    p = re.compile("/?([^/]+)\.gbk$")
    return [re.search(p, f).groups()[0] for f in files]


# create dictionary of accession numbers for each species
PX_accnums = {s: acc_nums(f"panx_data/{s}/input_GenBank") for s in PX_species}


wildcard_constraints:
    species=f"({'|'.join(PX_species)})",
    kind=f"({'|'.join(PX_ker_names)})",


rule PX_all:
    input:
        expand(
            "panx_data/{species}/pangraphs/pangraph-{kind}.json",
            species=PX_species,
            kind=PX_ker_names,
        ),
        "panx_data/benchmark/benchmark_compression.csv",
        "panx_data/benchmark/benchmark_summary.csv",


rule PX_gbk_to_fa:
    message:
        "converting genbank to fasta for {wildcards.species} - {wildcards.acc} "
    input:
        "panx_data/{species}/input_GenBank/{acc}.gbk",
    output:
        "panx_data/{species}/fa/{acc}.fa",
    conda:
        "../conda_envs/bioinfo_env.yml"
    shell:
        """
        python3 workflow_scripts/gbk_to_fa.py --gbk {input} --fa {output}
        """


# ------------- Test on real PanX data -----------


# for correct benchmarking needs to have pangraph binary present in the path.
rule PX_build_full_pangraph:
    message:
        "building full pangraph ({wildcards.kind}) for {wildcards.species}"
    input:
        lambda w: expand("panx_data/{{species}}/fa/{acc}.fa", acc=PX_accnums[w.species]),
    output:
        pg="panx_data/{species}/pangraphs/pangraph-{kind}.json",
        bm="panx_data/{species}/pangraphs/benchmark/pangraph-{kind}.txt",
    params:
        opt=lambda w: PX_ker_opt[w.kind],
    conda:
        "../conda_envs/pangraph_build_env.yml"
    shell:
        """
        echo "species = {wildcards.species}" > {output.bm}
        echo "kind = {wildcards.kind}" >> {output.bm}
        export JULIA_NUM_THREADS=8
        /usr/bin/time --verbose -o {output.bm} -a pangraph build --circular {params.opt} {input} > {output.pg}
        """


rule PX_summary_performance_benchmark:
    message:
        "Summary of pangraph performances"
    input:
        expand(
            "panx_data/{species}/pangraphs/benchmark/pangraph-{kind}.txt",
            species=PX_species,
            kind=PX_ker_names,
        ),
    output:
        csv="panx_data/benchmark/benchmark_summary.csv",
        pdf="panx_data/benchmark/benchmark_summary.pdf",
    conda:
        "../conda_envs/bioinfo_env.yml"
    shell:
        """
        python3 workflow_scripts/summary_benchmark.py {output.csv} {output.pdf} {input}
        """


rule PX_compression_benchmark:
    message:
        "Compression performances for species {wildcards.species}"
    input:
        pang=expand(
            "panx_data/{{species}}/pangraphs/pangraph-{kind}.json", kind=PX_ker_names
        ),
        fa=lambda w: expand(
            "panx_data/{{species}}/fa/{acc}.fa", acc=PX_accnums[w.species]
        ),
    output:
        json="panx_data/benchmark/{species}/compression.json",
    conda:
        "../conda_envs/bioinfo_env.yml"
    shell:
        """
        python3 workflow_scripts/compression_benchmark.py --fasta {input.fa} --pangraphs {input.pang} --out_json {output.json}
        """


rule PX_summary_compression_benchmark:
    message:
        "Summary of compression performances"
    input:
        expand("panx_data/benchmark/{species}/compression.json", species=PX_species),
    output:
        csv="panx_data/benchmark/benchmark_compression.csv",
        pdf="panx_data/benchmark/benchmark_compression.pdf",
    conda:
        "../conda_envs/bioinfo_env.yml"
    shell:
        """
        python3 workflow_scripts/compression_summary.py --jsons {input} --csv {output.csv} --pdf {output.pdf}
        """


# ------------- Test pairwise graphs vs graph merging -----------


# rule PX_projection_full_graph:
#     message:
#         "Creating projection graph for species {wildcards.species}"
#     input:
#         lambda w: expand("panx_data/{{species}}/fa/{acc}.fa", acc=ACC50[w.species]),
#     output:
#         "projections/{species}/full/pangraph_{kind}.json",
#     params:
#         opt=lambda w: PX_ker_opt[w.kind],
#     conda:
#         "../conda_envs/pangraph_build_env.yml"
#     shell:
#         """
#         export JULIA_NUM_THREADS=8
#         pangraph build --circular {params.opt} {input} > {output}
#         """

# rule PX_pairwise_graphs:
#     message:
#         "Building pairwise graph for strains {wildcards.s1} - {wildcards.s2} ({wildcards.species})"
#     input:
#         lambda w: expand("panx_data/{{species}}/fa/{acc}.fa", acc=ACC50[w.species]),
#     output:
#         "projections/{species}/pairwise/pangraph_{kind}_{s1}|{s2}.json",
#     params:
#         opt=lambda w: PX_ker_opt[w.kind],
#     conda:
#         "../conda_envs/pangraph_build_env.yml"
#     shell:
#         """
#         pangraph build --circular {params.opt} {input} > {output}
#         """

# rule PX_pairwise_projection:
#     message:
#         "project graph on strains {wildcards.s1} - {wildcards.s2} ({wildcards.species})"
#     input:
#         "projections/{species}/full/pangraph_{kind}.json"
#     output:
#         "projections/{species}/projected/pangraph_{kind}_{s1}|{s2}.json"
#     conda:
#         "../conda_envs/pangraph_build_env.yml"
#     shell:
#         """
#         pangraph marginalize -s {wildcards.s1},{wildcards.s2} > {output}
#         """

# rule PX_compare_projection_pairwise:
#     message:
#         "comparing projected graph to pairwise graph ({wildcards.s1} - {wildcards.s2} ; {wildcards.species})"
#     input:
#         pw=""
#         pj=""
#     output:
#         "projections/{species}/comparison/{s1}|{s2}.json"
#     shell:
#         ""
