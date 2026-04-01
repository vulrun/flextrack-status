import { Octokit } from "@octokit/rest";

const KEEP_LOGS_FOR_DAYS = parseInt(process.env.KEEP_LOGS_FOR_DAYS || "7", 10);
const token = process.env.GITHUB_TOKEN;
const repoFull = process.env.REPO_FULL;
const currentRunId = process.env.GITHUB_RUN_ID;

if (!token) {
  console.error("Missing GITHUB_TOKEN");
  process.exit(1);
}

const [owner, repo] = repoFull.split("/");
if (!owner && !repo) {
  console.error("Missing REPO INFO");
  process.exit(1);
}

const octokit = new Octokit({ auth: token });
const cutoffDate = new Date(Date.now() - KEEP_LOGS_FOR_DAYS * 24 * 60 * 60 * 1000);

async function deleteWorkflowRuns() {
  console.log("Fetching workflow runs...");

  let page = 1;
  let count = 0;

  while (true) {
    if (count > 1000) break;
    const { data } = await octokit.actions.listWorkflowRunsForRepo({
      owner,
      repo,
      page,
      per_page: 100,
    });

    const runs = data?.workflow_runs;
    if (!runs.length) break;

    for (const run of runs) {
      if (String(run?.id) === String(currentRunId)) {
        continue;
      }

      const createdAt = new Date(run?.created_at);
      if (createdAt < cutoffDate) {
        console.log(`Deleting workflow run ${run?.id} (${run?.created_at})`);

        await octokit.actions
          .deleteWorkflowRun({
            owner,
            repo,
            run_id: run.id,
          })
          .catch((e) => null);
        count++;
      }
    }

    page++;
  }
}

async function deleteArtifacts() {
  console.log("Fetching artifacts...");

  let page = 1;
  let count = 0;

  while (true) {
    if (count > 1000) break;
    const { data } = await octokit.actions.listArtifactsForRepo({
      owner,
      repo,
      page,
      per_page: 100,
    });

    const artifacts = data.artifacts;
    if (!artifacts.length) break;

    for (const artifact of artifacts) {
      const createdAt = new Date(artifact.created_at);

      if (createdAt < cutoffDate) {
        console.log(`Deleting artifact ${artifact.name} (${artifact.id})`);

        await octokit.actions
          .deleteArtifact({
            owner,
            repo,
            artifact_id: artifact.id,
          })
          .catch((e) => null);
        count++;
      }
    }

    page++;
  }
}

async function run() {
  console.log(`Cleaning repository: ${owner}/${repo}`);

  await deleteWorkflowRuns();
  await deleteArtifacts();

  console.log("Cleanup finished");
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
