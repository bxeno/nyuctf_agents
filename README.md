# LLM CTF Automation Guide

Two repositories are used to reproduce the whole experiment: LLM_CTF_Database and llm_ctf_automation. 
[LLM_CTF_Database](https://github.com/sj2790/LLM_CTF_Database) repository contains all CTF challenges. 
The [llm_ctf_automation](https://github.com/NickNameInvalid/llm_ctf_automation) repository is the framework needed for conducting the experiments.

**Step 1**

Clone the [llm_ctf_automation](https://github.com/NickNameInvalid/llm_ctf_automation) repository using the following command: <br>
```bash git clone git@github.com:NickNameInvalid/llm_ctf_automation.git``` <br>
Enter the llm_ctf_automation repository you just cloned using the command  <br>
```cd llm_ctf_automation```  <br>
Clone the [LLM_CTF_Database](https://github.com/sj2790/LLM_CTF_Database) repository with all the challenges using the following command:  <br>
```bash git clone git@github.com:sj2790/LLM_CTF_Database.git.```  <br>

**Step 2**

Install python environment according to the requirements.txt. One way to do this is using conda environment with the following command:  <br>
```conda create -n llm_ctf python=3.11```  <br>

**Step 3**

Setup docker container with setup.sh.  <br>
```bash setup.sh```  <br>

**Step 4**

For paper-version runs, use the repository-local `do_paper_eval.sh` runner instead of the original `do_eval.sh` loop. It auto-detects either the original `challenge_list.tsv` layout or the newer `test_dataset.json` layout from a sibling `LLM_CTF_Database` or `NYU_CTF_Bench` checkout.  <br>
```bash ./do_paper_eval.sh```  <br>
For a short validation run:  <br>
```bash python3 scripts/run_paper_eval.py --limit 1 --repeats 1 --debug```  <br>
