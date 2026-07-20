# SimpleProxy infrastructure

Linode上のSimpleProxyノードを、Terraform、Ansible、systemdで一括管理します。

## 管理範囲

- Terraform
  - Nanode 1 GBを既定で10台
  - LinodeアカウントのSSH公開鍵
  - 全ノード共通のCloud Firewall
  - 任意のNodeBalancer（TCP、Least Connections、接続ヘルスチェック）
  - Cloudflare R2上のremote stateとlock file
- Ansible
  - Linodeタグを使ったdynamic inventory
  - Java、固定バージョンのSimpleProxy JAR、実行ユーザー、systemd unit
  - 管理ユーザーとSSH公開鍵
  - graceful reload、2台ずつのrolling restart、OS更新
- 既存のGitHub同期処理
  - `config.yml`の配布

Ansibleは既存の設定同期処理を上書きしません。既定ではSimpleProxy 1.1.6の公式JARを
SHA-256検証付きで`/opt/simpleproxy/SimpleProxy.jar`へ配置します。更新時は
`group_vars/simpleproxy.yml`のURLとchecksumを必ず一緒に変更してください。

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

Variables:

| 名前 | 例 |
| --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Account ID |
| `R2_BUCKET_NAME` | `terraform-state` |
| `LINODE_REGION` | `ap-northeast` |
| `INSTANCE_COUNT` | `10` |
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

NodeBalancerを使う場合は`enable_nodebalancer = true`にし、backendへの通信を許可するため
`proxy_allowed_ipv4`へLinodeのlegacy private IPv4範囲も追加します。

```hcl
enable_nodebalancer = true
proxy_allowed_ipv4  = ["192.168.128.0/17"]
proxy_allowed_ipv6  = []
```

`nodebalancer_proxy_protocol`を`v1`または`v2`にする場合は、既存同期処理が配る
SimpleProxyの`config.yml`でもProxy Protocolを有効にしてください。

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

`update-os.yml`は2台ずつ更新し、必要な場合は再起動してからlistenerを確認します。

## R2 Stateの注意点

- Bucketは公開しない。
- Stateと`.tflock`の読み書き・削除に必要な権限をCIへ付与する。
- R2はS3互換Backendなので、Terraform更新時はlock動作を検証する。
- R2にはS3互換のBucket Versioningがないため、workflowがApply前に別キーへバックアップする。
- Stateには機密値が含まれ得るため、バックアップprefixも公開しない。
