# SimpleProxy infrastructure

Linode上のUbuntu 26.04 LTS SimpleProxyノードを、Terraform、Ansible、systemdで一括管理します。

## 管理範囲

- Terraform
  - Nanode 1 GBを既定で10台
  - LinodeアカウントのSSH公開鍵
  - 全ノード共通のCloud Firewall
  - 任意のNodeBalancer（TCP、Least Connections、接続ヘルスチェック）
  - Cloudflare R2上のremote stateとlock file
- Ansible
  - Linodeタグを使ったdynamic inventory
  - Ubuntu 26.04上のJava、固定バージョンのSimpleProxy JAR、実行ユーザー、systemd unit
  - Cloudflare One Clientの導入とService TokenによるCloudflare Meshへの自動登録
  - `relay-server-config`の固定コミットから`config.yml`を配布
  - 管理ユーザーとSSH公開鍵
  - graceful reload、2台ずつのrolling restart、OS更新

AnsibleはSimpleProxy 1.1.6の公式JARをSHA-256検証付きで
`/opt/simpleproxy/SimpleProxy.jar`へ配置します。更新時は`group_vars/simpleproxy.yml`の
URLとchecksumを必ず一緒に変更してください。

## 事前準備

1. Cloudflareで非公開のR2 Bucketを作成する。
2. そのBucketだけにObject Read & Writeを持つR2 API Tokenを作成する。
3. GitHubに`terraform-plan`と`production` Environmentを作成する。
4. `production` Environmentにrequired reviewersを設定する。
5. 下記のSecretsとVariablesを登録する。

Secrets:

| 名前 | 内容 |
| --- | --- |
| `LINODE_TOKEN` | Linodeの書き込み可能なAPI Token |
| `R2_ACCESS_KEY_ID` | R2のAccess Key ID |
| `R2_SECRET_ACCESS_KEY` | R2のSecret Access Key |
| `SSH_PUBLIC_KEY` | インスタンスへ投入するOpenSSH公開鍵 |
| `CLOUDFLARE_ZERO_TRUST_ORGANIZATION` | Cloudflare Zero Trustのteam name |
| `CLOUDFLARE_ACCESS_CLIENT_ID` | ヘッドレス登録用Service TokenのClient ID |
| `CLOUDFLARE_ACCESS_CLIENT_SECRET` | ヘッドレス登録用Service TokenのClient Secret |

Variables:

| 名前 | 例 |
| --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Account ID |
| `R2_BUCKET_NAME` | `terraform-state` |
| `LINODE_REGION` | `ap-northeast` |
| `PROXY_PORT` | `25565` |
| `SSH_ALLOWED_IPV4` | `["203.0.113.10/32"]` |
| `SSH_ALLOWED_IPV6` | `[]` |
| `PROXY_ALLOWED_IPV4` | `["0.0.0.0/0"]` |
| `PROXY_ALLOWED_IPV6` | `["::/0"]` |
| `ENABLE_NODEBALANCER` | `false` |
| `NODEBALANCER_ALGORITHM` | `leastconn` |
| `NODEBALANCER_PROXY_PROTOCOL` | `none` |

Secretsは両Environmentへ登録します。PRのplanで書き込み権限を渡したくない場合は、
`terraform-plan`ではLinodeとR2にread-onlyの別Tokenを使ってください。

インスタンス台数はGitHub Variableではなく、`terraform/variables.tf`の
`instance_count`にある`default`で管理します。台数変更はコード変更としてPull Requestに含めます。

## Terraformの運用

Pull Requestではformat、validate、planを実行します。forkからのPRはSecretsを渡さず、
formatとvalidateだけを実行します。

ApplyはActions画面から`Terraform` workflowを手動実行し、次の値を選びます。

```text
operation: apply
confirm_apply: APPLY
```

workflowは先にcandidate planを作り、1日で失効する非公開Artifactとして保存します。
planのログを確認してから`production` Environmentを承認すると、現在のStateをR2内の
`backups/proxy-infra/`へ退避し、承認対象と同一のplanをapplyします。
plan Artifactにも機密情報が含まれ得るため、Actionsへの閲覧権限を絞ってください。

ローカルからの`terraform apply`をコードだけで禁止することはできません。
運用上の強制力は、Linode書込TokenとR2書込鍵を`production` Environmentだけに置き、
開発者へ配布しないことで確保します。ローカルでは認証不要の次だけを使います。

```bash
cd terraform
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

NodeBalancerを使う場合は`enable_nodebalancer = true`にします。
`proxy_allowed_ipv4`と`proxy_allowed_ipv6`はNodeBalancer公開入口へ接続できる利用者の
CIDRとして、そのまま使用します。

```hcl
enable_nodebalancer = true
proxy_allowed_ipv4  = ["0.0.0.0/0"]
proxy_allowed_ipv6  = ["::/0"]
```

NodeBalancerを有効にすると、NodeBalancer専用Cloud Firewallを自動作成して上記CIDRから
`proxy_port`への通信だけを許可します。同時に各SimpleProxyのCloud Firewallは
`192.168.255.0/24`からのprivate IPv4通信だけを許可するルールへ切り替わるため、
各インスタンスの公開IPを使ったNodeBalancerの迂回はできなくなります。

NodeBalancerを無効に戻すと専用Firewallを削除し、各SimpleProxyのFirewallは再び
`proxy_allowed_ipv4`と`proxy_allowed_ipv6`を直接使用します。SSHの許可範囲はどちらの
場合も`ssh_allowed_ipv4`と`ssh_allowed_ipv6`のままです。

`nodebalancer_proxy_protocol`を`v1`または`v2`にする場合は、`relay-server-config`側の
SimpleProxy設定でもProxy Protocolを有効にしてください。

## Ansibleの運用

AnsibleコントローラーからLinode APIと各ノードへ到達できる必要があります。
GitHub-hosted runnerのIPをSSHへ広く許可せず、管理用ホスト、VPN、または
self-hosted runnerから実行してください。

```bash
cd ansible
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml

export LINODE_ACCESS_TOKEN="..."
ansible-inventory --graph
ansible-playbook site.yml
```

`site.yml`はCloudflare One Clientを導入し、上記3つの環境変数を使って各Linodeを
Cloudflare Meshへ登録します。GitHub Actionsから手動で構成だけを再適用する場合は
`Configure SimpleProxy nodes` workflowを実行してください。

バックエンドはCIDR routeではなく、次のMesh IPへ直接接続します。

| バックエンド | Mesh IP | 疎通確認ポート |
| --- | --- | --- |
| 旧 `10.0.0.108` | `172.31.240.1` | `30500` |
| 旧 `10.0.0.110` | `172.31.240.4` | `30500` |

これらのIP割り当てと、`172.31.240.0/24`をCloudflare One Clientへ通すSplit Tunnel設定は
Cloudflare Zero Trust側で管理します。設定デプロイは全Linodeで`warp-cli status`が
Connectedとなり、両バックエンドの30500番へ接続できる場合だけ続行します。

`requirements.txt`はコントローラーのPythonに応じてAnsible Coreを選択します。
Python 3.10ではCore 2.17、Python 3.11以上では互換性のある2.19または2.20が入ります。
Core 2.17は既にEOLのため、可能になり次第コントローラーをPython 3.11以上へ更新してください。

初回はTerraformが投入したroot鍵で接続します。管理ユーザーを作る場合は、
`group_vars/simpleproxy.yml`の`simpleproxy_admin_authorized_keys`へ公開鍵を設定し、
`site.yml`を適用します。接続確認後に`ansible_user`を`proxyadmin`へ変更できます。

日常操作はこちらです。

```bash
ansible-playbook reload.yml
ansible-playbook rolling-restart.yml
ansible-playbook update-os.yml
ansible simpleproxy -b -m ansible.builtin.systemd_service \
  -a "name=simpleproxy state=started"
```

## SimpleProxy設定のデプロイ

配布する設定のコミットは`ansible/group_vars/simpleproxy.yml`で固定します。

```yaml
simpleproxy_config_commit: "3db74db5587e7738ffe80acaa7dcae7c04451a30"
```

このSHAを変更するPull Requestがmainへマージされると、`Deploy SimpleProxy config`
workflowがself-hosted Linux runner上で起動します。runnerは次を実行します。

1. `relay-server-config`を取得して指定SHAをcheckoutする。
2. SHAが`generated`ブランチに含まれることと、生成ファイルが有効なYAMLであることを確認する。
3. 旧`10.0.0.108`/`10.0.0.110`が残っておらず、Mesh IPが含まれることを確認する。
4. `site.yml`を適用してCloudflare Mesh接続を構成する。
5. 全ノードからMeshバックエンドへの疎通を確認する。
6. `ip-deny-list/generated/simpleproxy-config.yml`を全ノードの
   `/opt/simpleproxy/config.yml`へ2台ずつ原子的に転送する。
7. 変更されたノードだけSIGHUPでreloadし、25565番listenerを確認する。

self-hosted runnerの実行ユーザーには、次の両方へのSSHアクセスが必要です。

- `git@github.com:azisaba/relay-server-config.git`の読み取り
- SimpleProxyノードへのroot SSH（または`ansible_user`で指定した管理ユーザー）

SimpleProxyノードへの接続には、runner実行ユーザーの次の秘密鍵を使用します。

```text
~/.ssh/simpleproxy_ed25519
```

所有者をrunner実行ユーザー、パーミッションを`0600`にしてください。この指定は
`deploy-config.yml`だけでなく、`site.yml`やreloadなど全SimpleProxy向けPlaybookで共通です。

初回の設定デプロイ前に一度`ansible-playbook site.yml`を実行し、各ノードへ
`simpleproxy`ユーザー、JAR、systemd unitを作成してください。

手動で再実行する場合はActions画面の`Deploy SimpleProxy config`から
`Run workflow`を選びます。ロールバックは`simpleproxy_config_commit`を以前のSHAへ戻す
Pull Requestをマージします。`production` Environmentにrequired reviewersがある場合は、
自動起動後に承認されるまでデプロイは待機します。

`update-os.yml`は2台ずつ更新し、必要な場合は再起動してからlistenerを確認します。

## R2 Stateの注意点

- Bucketは公開しない。
- Stateと`.tflock`の読み書き・削除に必要な権限をCIへ付与する。
- R2はS3互換Backendなので、Terraform更新時はlock動作を検証する。
- R2にはS3互換のBucket Versioningがないため、workflowがApply前に別キーへバックアップする。
- Stateには機密値が含まれ得るため、バックアップprefixも公開しない。
