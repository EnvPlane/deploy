package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"
)

type config struct {
	Mode               string
	Namespace          string
	ProjectID          string
	ClusterID          string
	AgentID            string
	RunnerID           string
	RunnerNamespace    string
	RunnerReleaseName  string
	DeploymentMode     string
	ControlPlaneRel    string
	AgentRel           string
	RunnerRel          string
	GHCRSecret         string
	GHCRServer         string
	GHCRUsername       string
	GHCRToken          string
	APIImage           string
	FrontendImage      string
	AgentImage         string
	RunnerImage        string
	ImageTag           string
	ImagePullPolicy    string
	StorageClass       string
	NodeArch           string
	TolerationKey      string
	TolerationValue    string
	TolerationEffect   string
	ProductID          string
	AppRepositoryID    string
	GitOpsRepositoryID string
	PostgresPassword   string
	ChartsDir          string
	LocalPort          int
	Timeout            time.Duration
	SkipRegistrySecret bool
	SeedProject        bool
	PreserveNamespace  bool
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	cfg := parseFlags()
	if err := run(ctx, cfg); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func parseFlags() config {
	var cfg config
	flag.StringVar(&cfg.Mode, "mode", getenv("ENVPILOT_INSTALL_MODE", "install"), "install or clean-install")
	flag.StringVar(&cfg.Namespace, "namespace", getenv("ENVPILOT_NAMESPACE", "envpilot"), "Kubernetes namespace")
	flag.StringVar(&cfg.ProjectID, "project-id", getenv("ENVPILOT_PROJECT_ID", "default"), "EnvPilot project id")
	flag.StringVar(&cfg.ClusterID, "cluster-id", getenv("ENVPILOT_CLUSTER_ID", ""), "cluster id reported by agent/runner")
	flag.StringVar(&cfg.AgentID, "agent-id", getenv("ENVPILOT_AGENT_ID", "envpilot-agent"), "agent id")
	flag.StringVar(&cfg.RunnerID, "runner-id", getenv("ENVPILOT_RUNNER_ID", ""), "runner id")
	flag.StringVar(&cfg.RunnerNamespace, "runner-namespace", getenv("ENVPILOT_RUNNER_NAMESPACE", ""), "runner namespace")
	flag.StringVar(&cfg.RunnerReleaseName, "runner-release-name", getenv("ENVPILOT_RUNNER_RELEASE_NAME", ""), "unique runner bootstrap release name")
	flag.StringVar(&cfg.DeploymentMode, "runner-deployment-mode", getenv("ENVPILOT_RUNNER_DEPLOYMENT_MODE", "helm"), "runner deployment mode")
	flag.StringVar(&cfg.ControlPlaneRel, "control-plane-release", getenv("ENVPILOT_CONTROL_PLANE_RELEASE", "envpilot"), "control-plane Helm release")
	flag.StringVar(&cfg.AgentRel, "agent-release", getenv("ENVPILOT_AGENT_RELEASE", "envpilot-agent"), "agent Helm release")
	flag.StringVar(&cfg.RunnerRel, "runner-release", getenv("ENVPILOT_RUNNER_RELEASE", "envpilot-runner"), "runner Helm release")
	flag.StringVar(&cfg.GHCRSecret, "ghcr-secret", getenv("ENVPILOT_GHCR_SECRET", "ghcr-envpilot"), "image pull secret name")
	flag.StringVar(&cfg.GHCRServer, "ghcr-server", getenv("ENVPILOT_GHCR_SERVER", "ghcr.io"), "registry server")
	flag.StringVar(&cfg.GHCRUsername, "ghcr-username", getenv("ENVPILOT_GHCR_USERNAME", "envpilot"), "registry username")
	flag.StringVar(&cfg.GHCRToken, "ghcr-token", getenv("ENVPILOT_GHCR_TOKEN", ""), "registry token; falls back to gh auth token")
	flag.StringVar(&cfg.APIImage, "api-image", getenv("ENVPILOT_API_IMAGE", "ghcr.io/envpilot/api"), "API image repository")
	flag.StringVar(&cfg.FrontendImage, "frontend-image", getenv("ENVPILOT_FRONTEND_IMAGE", "ghcr.io/envpilot/frontend"), "frontend image repository")
	flag.StringVar(&cfg.AgentImage, "agent-image", getenv("ENVPILOT_AGENT_IMAGE", "ghcr.io/envpilot/agent"), "agent image repository")
	flag.StringVar(&cfg.RunnerImage, "runner-image", getenv("ENVPILOT_RUNNER_IMAGE", "ghcr.io/envpilot/runner"), "runner image repository")
	flag.StringVar(&cfg.ImageTag, "image-tag", getenv("ENVPILOT_IMAGE_TAG", "0.1.0"), "image tag")
	flag.StringVar(&cfg.ImagePullPolicy, "image-pull-policy", getenv("ENVPILOT_IMAGE_PULL_POLICY", "Always"), "image pull policy")
	flag.StringVar(&cfg.StorageClass, "storage-class", getenv("ENVPILOT_STORAGE_CLASS", ""), "storage class for PVCs")
	flag.StringVar(&cfg.NodeArch, "node-arch", getenv("ENVPILOT_NODE_ARCH", ""), "optional kubernetes.io/arch node selector")
	flag.StringVar(&cfg.TolerationKey, "toleration-key", getenv("ENVPILOT_TOLERATION_KEY", ""), "optional toleration key")
	flag.StringVar(&cfg.TolerationValue, "toleration-value", getenv("ENVPILOT_TOLERATION_VALUE", ""), "optional toleration value")
	flag.StringVar(&cfg.TolerationEffect, "toleration-effect", getenv("ENVPILOT_TOLERATION_EFFECT", "NoSchedule"), "optional toleration effect")
	flag.StringVar(&cfg.ProductID, "product-id", getenv("ENVPILOT_PRODUCT_ID", "default"), "seeded EnvPilot product id")
	flag.StringVar(&cfg.AppRepositoryID, "app-repository-id", getenv("ENVPILOT_APP_REPOSITORY_ID", "envpilot/app"), "seeded app repository id")
	flag.StringVar(&cfg.GitOpsRepositoryID, "gitops-repository-id", getenv("ENVPILOT_GITOPS_REPOSITORY_ID", "envpilot/gitops"), "seeded GitOps repository id")
	flag.StringVar(&cfg.PostgresPassword, "postgres-password", getenv("ENVPILOT_POSTGRES_PASSWORD", "envpilot"), "control-plane Postgres password")
	flag.StringVar(&cfg.ChartsDir, "charts-dir", getenv("ENVPILOT_CHARTS_DIR", ""), "charts dir; defaults to repo deploy/helm")
	flag.IntVar(&cfg.LocalPort, "local-port", getenvInt("ENVPILOT_LOCAL_PORT", 18080), "local port-forward port")
	flag.DurationVar(&cfg.Timeout, "timeout", time.Duration(getenvInt("ENVPILOT_INSTALL_TIMEOUT_SECONDS", 240))*time.Second, "rollout/API timeout")
	flag.BoolVar(&cfg.SkipRegistrySecret, "skip-registry-secret", getenvBool("ENVPILOT_SKIP_REGISTRY_SECRET", false), "do not create registry pull secret")
	flag.BoolVar(&cfg.SeedProject, "seed-project", getenvBool("ENVPILOT_SEED_PROJECT", true), "seed minimal project/config before bootstrap")
	flag.BoolVar(&cfg.PreserveNamespace, "preserve-namespace-cleanup", getenvBool("ENVPILOT_PRESERVE_NAMESPACE_CLEANUP", false), "clean releases and PVCs without deleting namespace")
	flag.Parse()
	if cfg.RunnerID == "" {
		cfg.RunnerID = cfg.ProjectID + "-runner"
	}
	if cfg.RunnerNamespace == "" {
		cfg.RunnerNamespace = cfg.Namespace
	}
	if cfg.RunnerReleaseName == "" {
		cfg.RunnerReleaseName = fmt.Sprintf("%s-%d", cfg.RunnerRel, time.Now().Unix())
	}
	if cfg.ChartsDir == "" {
		cfg.ChartsDir = defaultChartsDir()
	}
	return cfg
}

func run(ctx context.Context, cfg config) error {
	if cfg.ClusterID == "" {
		return errors.New("cluster id is required: set --cluster-id or ENVPILOT_CLUSTER_ID")
	}
	for _, name := range []string{"kubectl", "helm"} {
		if _, err := exec.LookPath(name); err != nil {
			return fmt.Errorf("missing required command %s: %w", name, err)
		}
	}
	if cfg.Mode == "clean-install" {
		if err := clean(ctx, cfg); err != nil {
			return err
		}
	} else if cfg.Mode != "install" {
		return fmt.Errorf("unsupported mode %q", cfg.Mode)
	}
	if err := createNamespaceAndRegistrySecret(ctx, cfg); err != nil {
		return err
	}
	if err := installControlPlane(ctx, cfg); err != nil {
		return err
	}
	if cfg.SeedProject {
		if err := seedProject(ctx, cfg); err != nil {
			return err
		}
	}
	pf, err := startPortForward(ctx, cfg)
	if err != nil {
		return err
	}
	defer pf()
	if err := createBootstrapSecrets(ctx, cfg); err != nil {
		return err
	}
	if err := installAgent(ctx, cfg); err != nil {
		return err
	}
	if err := installRunner(ctx, cfg); err != nil {
		return err
	}
	return runCmd(ctx, "kubectl", "get", "pods,pvc", "-n", cfg.Namespace)
}

func clean(ctx context.Context, cfg config) error {
	_ = runCmd(ctx, "helm", "uninstall", cfg.RunnerRel, "-n", cfg.Namespace, "--ignore-not-found")
	_ = runCmd(ctx, "helm", "uninstall", cfg.AgentRel, "-n", cfg.Namespace, "--ignore-not-found")
	_ = runCmd(ctx, "helm", "uninstall", cfg.ControlPlaneRel, "-n", cfg.Namespace, "--ignore-not-found")
	if cfg.PreserveNamespace {
		_ = runCmd(ctx, "kubectl", "delete", "pvc", "-n", cfg.Namespace, "--ignore-not-found",
			"data-"+cfg.ControlPlaneRel+"-control-plane-postgres-0",
			"data-"+cfg.ControlPlaneRel+"-control-plane-redis-0",
			cfg.AgentRel+"-envpilot-agent-chart-auth",
			cfg.RunnerRel+"-envpilot-runner-chart-auth",
		)
		_ = runCmd(ctx, "kubectl", "delete", "secret", "-n", cfg.Namespace, "--ignore-not-found",
			cfg.GHCRSecret,
			"envpilot-agent-bootstrap",
			"envpilot-runner-bootstrap",
		)
	} else {
		_ = runCmd(ctx, "kubectl", "delete", "namespace", cfg.Namespace, "--ignore-not-found", "--wait=true")
	}
	_ = runCmd(ctx, "kubectl", "delete", "clusterrole", cfg.AgentRel+"-envpilot-agent-chart", cfg.RunnerRel+"-envpilot-runner-chart-discovery-reader", "--ignore-not-found")
	_ = runCmd(ctx, "kubectl", "delete", "clusterrolebinding", cfg.AgentRel+"-envpilot-agent-chart", cfg.RunnerRel+"-envpilot-runner-chart-discovery-reader", "--ignore-not-found")
	return nil
}

func createNamespaceAndRegistrySecret(ctx context.Context, cfg config) error {
	if err := runPipe(ctx, []string{"kubectl", "create", "namespace", cfg.Namespace, "--dry-run=client", "-o", "yaml"}, []string{"kubectl", "apply", "-f", "-"}); err != nil {
		return err
	}
	if cfg.SkipRegistrySecret {
		return nil
	}
	token := cfg.GHCRToken
	if token == "" {
		out, err := commandOutput(ctx, "gh", "auth", "token", "--hostname", "github.com")
		if err != nil {
			return fmt.Errorf("set --ghcr-token/ENVPILOT_GHCR_TOKEN or login with gh: %w", err)
		}
		token = strings.TrimSpace(out)
	}
	return runPipe(ctx,
		[]string{"kubectl", "create", "secret", "docker-registry", cfg.GHCRSecret, "--namespace", cfg.Namespace, "--docker-server", cfg.GHCRServer, "--docker-username", cfg.GHCRUsername, "--docker-password", token, "--dry-run=client", "-o", "yaml"},
		[]string{"kubectl", "apply", "-f", "-"},
	)
}

func installControlPlane(ctx context.Context, cfg config) error {
	args := []string{"upgrade", "--install", cfg.ControlPlaneRel, filepath.Join(cfg.ChartsDir, "envpilot-control-plane"), "--namespace", cfg.Namespace}
	args = appendSets(args, "image.repository", cfg.APIImage, "image.tag", cfg.ImageTag, "image.pullPolicy", cfg.ImagePullPolicy)
	args = appendSets(args, "frontend.image.repository", cfg.FrontendImage, "frontend.image.tag", cfg.ImageTag, "frontend.image.pullPolicy", cfg.ImagePullPolicy)
	args = appendSets(args, "imagePullSecrets[0].name", cfg.GHCRSecret, "dependencyWait.enabled", "true")
	args = appendSets(args, "env.ENVPILOT_DEPENDENCY_WAIT_TIMEOUT_SECONDS", "120", "env.ENVPILOT_DEPENDENCY_WAIT_INTERVAL_SECONDS", "2")
	if cfg.StorageClass != "" {
		args = appendSets(args, "postgres.persistence.storageClassName", cfg.StorageClass, "redis.persistence.storageClassName", cfg.StorageClass)
	}
	args = append(args, schedulingSets("", cfg)...)
	args = append(args, schedulingSets("frontend.", cfg)...)
	if err := runCmd(ctx, "helm", args...); err != nil {
		return err
	}
	if err := runCmd(ctx, "kubectl", "rollout", "status", "deployment/envpilot-control-plane", "-n", cfg.Namespace, "--timeout", timeoutArg(cfg)); err != nil {
		return err
	}
	return runCmd(ctx, "kubectl", "rollout", "status", "deployment/envpilot-control-plane-frontend", "-n", cfg.Namespace, "--timeout", timeoutArg(cfg))
}

func seedProject(ctx context.Context, cfg config) error {
	projectPayload, err := json.Marshal(map[string]any{
		"id":                    cfg.ProjectID,
		"name":                  cfg.ProjectID,
		"product_id":            cfg.ProductID,
		"app_repository_id":     cfg.AppRepositoryID,
		"gitops_repository_id":  cfg.GitOpsRepositoryID,
		"cluster_id":            cfg.ClusterID,
		"git_repo":              repositoryRef(cfg.AppRepositoryID),
		"gitops_repo":           repositoryRef(cfg.GitOpsRepositoryID),
		"default_branch":        "main",
		"preview_url_template":  "https://{{ .EnvID }}.example.local",
		"base_env_config":       map[string]any{"namespace": "shared", "deploymentBackend": "helm_direct"},
		"deploymentBackend":     "helm_direct",
		"environment_namespace": cfg.Namespace,
	})
	if err != nil {
		return err
	}
	configPayload, err := json.Marshal(map[string]any{
		"projectId": cfg.ProjectID,
		"deployment": map[string]any{
			"backend": "helm_direct",
			"helmDirect": map[string]any{
				"namespaceMode":      "per_environment",
				"namespacePattern":   "envpilot-{{ .EnvironmentID }}",
				"releaseNamePattern": "envpilot-{{ .EnvironmentID }}",
				"chartPath":          "./deploy/helm/envpilot-runner",
				"timeout":            "5m",
				"wait":               true,
				"createNamespace":    true,
			},
		},
		"cluster": map[string]any{
			"id":        cfg.ClusterID,
			"namespace": cfg.Namespace,
		},
	})
	if err != nil {
		return err
	}
	sessionPayload, err := json.Marshal(map[string]any{
		"runnerNamespace":      cfg.RunnerNamespace,
		"runnerDeploymentMode": cfg.DeploymentMode,
		"deployment":           map[string]any{"backend": "helm_direct"},
	})
	if err != nil {
		return err
	}
	sql := fmt.Sprintf(`
INSERT INTO projects (id, payload, product_id, app_repository_id, gitops_repository_id, cluster_id, created_at, updated_at)
VALUES (%[1]s, %[2]s::jsonb, %[3]s, %[4]s, %[5]s, %[6]s, now(), now())
ON CONFLICT (id) DO UPDATE SET
	payload = EXCLUDED.payload,
	product_id = EXCLUDED.product_id,
	app_repository_id = EXCLUDED.app_repository_id,
	gitops_repository_id = EXCLUDED.gitops_repository_id,
	cluster_id = EXCLUDED.cluster_id,
	updated_at = now();

DELETE FROM bootstrap_sessions WHERE project_id = %[1]s;

INSERT INTO bootstrap_sessions (id, project_id, current_step, status, created_by, data, created_at, updated_at)
VALUES (%[7]s, %[1]s, 1, 'compiled', 'envpilot-install', %[8]s::jsonb, now(), now());

INSERT INTO project_config_versions (id, project_id, version, config, created_at, created_by)
VALUES (%[10]s, %[1]s, 1, %[9]s::jsonb, now(), 'envpilot-install')
ON CONFLICT (project_id, version) DO UPDATE SET
	config = EXCLUDED.config,
	created_at = now(),
	created_by = EXCLUDED.created_by;
`, sqlLiteral(cfg.ProjectID), sqlLiteral(string(projectPayload)), sqlLiteral(cfg.ProductID), sqlLiteral(cfg.AppRepositoryID), sqlLiteral(cfg.GitOpsRepositoryID), sqlLiteral(cfg.ClusterID), sqlLiteral(cfg.ProjectID+"-bootstrap"), sqlLiteral(string(sessionPayload)), sqlLiteral(string(configPayload)), sqlLiteral(cfg.ProjectID+"-config-v1"))

	return runCmdInput(ctx, sql, "kubectl", "exec", "-i", "-n", cfg.Namespace, "envpilot-control-plane-postgres-0", "--", "env", "PGPASSWORD="+cfg.PostgresPassword, "psql", "-U", "envpilot", "-d", "envpilot", "-v", "ON_ERROR_STOP=1", "-f", "-")
}

func createBootstrapSecrets(ctx context.Context, cfg config) error {
	agentToken, err := createAgentToken(ctx, cfg)
	if err != nil {
		return err
	}
	if err := runPipe(ctx, []string{"kubectl", "create", "secret", "generic", "envpilot-agent-bootstrap", "--namespace", cfg.Namespace, "--from-literal=registration-token=" + agentToken, "--dry-run=client", "-o", "yaml"}, []string{"kubectl", "apply", "-f", "-"}); err != nil {
		return err
	}
	runnerToken, configToken, err := createRunnerTokens(ctx, cfg)
	if err != nil {
		return err
	}
	return runPipe(ctx, []string{"kubectl", "create", "secret", "generic", "envpilot-runner-bootstrap", "--namespace", cfg.Namespace, "--from-literal=token=" + runnerToken, "--from-literal=project-config-token=" + configToken, "--dry-run=client", "-o", "yaml"}, []string{"kubectl", "apply", "-f", "-"})
}

func installAgent(ctx context.Context, cfg config) error {
	args := []string{"upgrade", "--install", cfg.AgentRel, filepath.Join(cfg.ChartsDir, "envpilot-agent"), "--namespace", cfg.Namespace}
	args = appendSets(args, "image.repository", cfg.AgentImage, "image.tag", cfg.ImageTag, "image.pullPolicy", cfg.ImagePullPolicy)
	args = appendSets(args, "imagePullSecrets[0].name", cfg.GHCRSecret, "controlPlane.url", serviceURL(cfg), "controlPlane.existingSecret", "envpilot-agent-bootstrap")
	args = appendSets(args, "cluster.id", cfg.ClusterID, "bootstrap.projectId", cfg.ProjectID, "agent.id", cfg.AgentID)
	args = appendSets(args, "dependencyWait.enabled", "true", "dependencyWait.healthPath", "/api/v1/health", "agent.authPersistence.createClaim", "true")
	if cfg.StorageClass != "" {
		args = append(args, set("agent.authPersistence.storageClassName", cfg.StorageClass)...)
	}
	args = appendSets(args, "agent.authPersistence.size", "1Mi", "agent.authPersistence.accessModes[0]", "ReadWriteOnce")
	args = appendSets(args, "installValidation.enabled", "false", "ttlCleanup.enabled", "false")
	args = append(args, schedulingSets("", cfg)...)
	if err := runCmd(ctx, "helm", args...); err != nil {
		return err
	}
	return runCmd(ctx, "kubectl", "rollout", "status", "deployment/envpilot-agent-chart", "-n", cfg.Namespace, "--timeout", timeoutArg(cfg))
}

func installRunner(ctx context.Context, cfg config) error {
	args := []string{"upgrade", "--install", cfg.RunnerRel, filepath.Join(cfg.ChartsDir, "envpilot-runner"), "--namespace", cfg.Namespace}
	args = appendSets(args, "image.repository", cfg.RunnerImage, "image.tag", cfg.ImageTag, "image.pullPolicy", cfg.ImagePullPolicy)
	args = appendSets(args, "imagePullSecrets[0].name", cfg.GHCRSecret, "controlPlane.url", serviceURL(cfg), "controlPlane.existingSecret", "envpilot-runner-bootstrap")
	args = appendSets(args, "project.id", cfg.ProjectID, "project.clusterId", cfg.ClusterID, "project.runnerId", cfg.RunnerID, "project.namespace", cfg.RunnerNamespace, "project.deploymentMode", cfg.DeploymentMode)
	args = appendSets(args, "project.configUrl", fmt.Sprintf("%s/api/v1/projects/%s/runner-config", serviceURL(cfg), cfg.ProjectID), "dependencyWait.enabled", "true", "dependencyWait.healthPath", "/api/v1/health")
	args = append(args, set("controlPlane.authPersistence.createClaim", "true")...)
	if cfg.StorageClass != "" {
		args = append(args, set("controlPlane.authPersistence.storageClassName", cfg.StorageClass)...)
	}
	args = appendSets(args, "controlPlane.authPersistence.size", "1Mi", "controlPlane.authPersistence.accessModes[0]", "ReadWriteOnce")
	args = append(args, schedulingSets("", cfg)...)
	if err := runCmd(ctx, "helm", args...); err != nil {
		return err
	}
	return runCmd(ctx, "kubectl", "rollout", "status", "deployment/envpilot-runner-chart", "-n", cfg.Namespace, "--timeout", timeoutArg(cfg))
}

func createAgentToken(ctx context.Context, cfg config) (string, error) {
	var resp struct {
		RegistrationToken string `json:"registrationToken"`
	}
	if err := postJSON(ctx, cfg, fmt.Sprintf("/api/projects/%s/bootstrap-session/agent-token", cfg.ProjectID), map[string]string{"clusterId": cfg.ClusterID, "agentId": cfg.AgentID}, &resp); err != nil {
		return "", err
	}
	if resp.RegistrationToken == "" {
		return "", errors.New("control-plane returned empty agent registration token")
	}
	return resp.RegistrationToken, nil
}

func createRunnerTokens(ctx context.Context, cfg config) (string, string, error) {
	var resp struct {
		BootstrapSecretCommand string `json:"bootstrapSecretCommand"`
	}
	body := map[string]string{"deploymentMode": cfg.DeploymentMode, "clusterId": cfg.ClusterID, "runnerNamespace": cfg.RunnerNamespace, "releaseName": cfg.RunnerReleaseName}
	if err := postJSON(ctx, cfg, fmt.Sprintf("/api/projects/%s/bootstrap-session/runner-deployment-instructions", cfg.ProjectID), body, &resp); err != nil {
		return "", "", err
	}
	runnerToken := extractLiteral(resp.BootstrapSecretCommand, "token")
	configToken := extractLiteral(resp.BootstrapSecretCommand, "project-config-token")
	if runnerToken == "" || configToken == "" || runnerToken == "[masked]" || configToken == "[masked]" {
		return "", "", errors.New("control-plane did not return unmasked runner bootstrap tokens; use a fresh --runner-release-name")
	}
	return runnerToken, configToken, nil
}

func postJSON(ctx context.Context, cfg config, path string, body any, target any) error {
	payload, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, fmt.Sprintf("http://127.0.0.1:%d%s", cfg.LocalPort, path), bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		data, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("POST %s failed: status=%d body=%s", path, resp.StatusCode, strings.TrimSpace(string(data)))
	}
	return json.NewDecoder(resp.Body).Decode(target)
}

func startPortForward(ctx context.Context, cfg config) (func(), error) {
	pfCtx, cancel := context.WithCancel(ctx)
	cmd := exec.CommandContext(pfCtx, "kubectl", "port-forward", "-n", cfg.Namespace, "svc/envpilot-control-plane", fmt.Sprintf("%d:8080", cfg.LocalPort))
	var stderr bytes.Buffer
	cmd.Stdout = io.Discard
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		cancel()
		return nil, err
	}
	cleanup := func() { cancel(); _ = cmd.Wait() }
	deadline := time.Now().Add(cfg.Timeout)
	for time.Now().Before(deadline) {
		resp, err := http.Get(fmt.Sprintf("http://127.0.0.1:%d/api/v1/health", cfg.LocalPort))
		if err == nil {
			_ = resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return cleanup, nil
			}
		}
		time.Sleep(time.Second)
	}
	cleanup()
	return nil, fmt.Errorf("control-plane port-forward did not become ready: %s", stderr.String())
}

func runCmd(ctx context.Context, name string, args ...string) error {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func runCmdInput(ctx context.Context, input string, name string, args ...string) error {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdin = strings.NewReader(input)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func commandOutput(ctx context.Context, name string, args ...string) (string, error) {
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

func runPipe(ctx context.Context, first []string, second []string) error {
	left := exec.CommandContext(ctx, first[0], first[1:]...)
	right := exec.CommandContext(ctx, second[0], second[1:]...)
	pipe, err := left.StdoutPipe()
	if err != nil {
		return err
	}
	left.Stderr = os.Stderr
	right.Stdin = pipe
	right.Stdout = os.Stdout
	right.Stderr = os.Stderr
	if err := left.Start(); err != nil {
		return err
	}
	if err := right.Start(); err != nil {
		return err
	}
	leftErr := left.Wait()
	rightErr := right.Wait()
	if leftErr != nil {
		return leftErr
	}
	return rightErr
}

func set(key string, value string) []string { return []string{"--set", key + "=" + value} }

func appendSets(args []string, pairs ...string) []string {
	for i := 0; i+1 < len(pairs); i += 2 {
		args = append(args, set(pairs[i], pairs[i+1])...)
	}
	return args
}

func schedulingSets(prefix string, cfg config) []string {
	var args []string
	if cfg.NodeArch != "" {
		args = append(args, set(prefix+"nodeSelector.kubernetes\\.io/arch", cfg.NodeArch)...)
	}
	if cfg.TolerationKey != "" {
		args = append(args, set(prefix+"tolerations[0].key", cfg.TolerationKey)...)
		args = append(args, set(prefix+"tolerations[0].operator", "Equal")...)
		args = append(args, set(prefix+"tolerations[0].value", cfg.TolerationValue)...)
		args = append(args, set(prefix+"tolerations[0].effect", cfg.TolerationEffect)...)
	}
	return args
}

func serviceURL(cfg config) string {
	return fmt.Sprintf("http://envpilot-control-plane.%s.svc.cluster.local:8080", cfg.Namespace)
}

func timeoutArg(cfg config) string { return fmt.Sprintf("%ds", int(cfg.Timeout.Seconds())) }

func repositoryRef(id string) map[string]string {
	return map[string]string{
		"provider":       "github",
		"url":            "https://github.com/" + strings.TrimPrefix(id, "github.com/"),
		"default_branch": "main",
	}
}

func sqlLiteral(value string) string {
	tag := "$envpilot$"
	for strings.Contains(value, tag) {
		tag = tag[:len(tag)-1] + "x$"
	}
	return tag + value + tag
}

func getenv(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func getenvBool(key string, fallback bool) bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	if v == "" {
		return fallback
	}
	return v == "1" || v == "true" || v == "yes"
}

func getenvInt(key string, fallback int) int {
	var v int
	if _, err := fmt.Sscanf(strings.TrimSpace(os.Getenv(key)), "%d", &v); err == nil {
		return v
	}
	return fallback
}

func defaultChartsDir() string {
	if _, err := os.Stat("deploy/helm/envpilot-control-plane"); err == nil {
		return "deploy/helm"
	}
	if _, err := os.Stat("deploy/deploy/helm/envpilot-control-plane"); err == nil {
		return "deploy/deploy/helm"
	}
	if _, err := os.Stat("helm/envpilot-control-plane"); err == nil {
		return "helm"
	}
	return "deploy/helm"
}

func extractLiteral(command string, key string) string {
	re := regexp.MustCompile(`--from-literal=` + regexp.QuoteMeta(key) + `="([^"]*)"`)
	match := re.FindStringSubmatch(command)
	if len(match) != 2 {
		return ""
	}
	return match[1]
}
