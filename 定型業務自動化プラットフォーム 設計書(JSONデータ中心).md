# 定型業務自動化プラットフォーム 設計書

## 1. 文書目的

本書は、既存のJira Service Portal / Jira ITSMを受付・承認基盤として利用し、IBM Concert Workflows、GitHub、HCP Terraform、HCP Vault等を組み合わせて、オンプレミス・クラウド・SaaSにまたがる定型業務を自動化するための基本設計を整理するものである。

今回の代表ユースケースとしてDNS管理業務を対象とし、以下の自動化を想定する。

- DNSレコードの追加・変更・削除
- Hosted Zoneの追加・変更・削除
- Health Check（モニター）の追加・変更・削除
- Traffic Routingの設定・変更・解除

本設計では、個別の自動化処理を作るだけでなく、今後複数の定型業務へ横展開可能な「企業共通の自動化プラットフォーム」を構築することを目的とする。

---

# 2. 背景

現在、定型的な運用作業の多くがJira等で申請・承認された後、人手によって実行されている。

本提案では、既存のJira Service Portalを変更申請の入口および業務状態管理のSystem of Recordとして維持しつつ、承認済みの作業要求を自動化プラットフォームへ連携し、標準化された処理として実行する。

今回対象とするのは、あらかじめ手順と実行条件を定義可能な定型業務である。

インシデント分析、原因分析、復旧判断、Self-Healing等の自律型インシデント対応は本スコープに含めない。

---

# 3. 基本設計思想

本基盤では、責任を以下の3層へ分離する。

```text
┌─────────────────────────────┐
│ Business State / Approval   │
│ Jira                        │
└─────────────┬───────────────┘
              │
              ↓
┌─────────────────────────────┐
│ Automation Control Plane    │
│ Concert Workflows           │
└─────────────┬───────────────┘
              │
      ┌───────┼─────────┐
      ↓       ↓         ↓
 Terraform  Worker     API
      │       │         │
    Cloud   On-prem    SaaS
```

## 3.1 Jira

Jiraは以下を担当する。

- サービスポータル
- 利用者からの申請受付
- 申請情報管理
- 承認
- チケット状態管理
- 利用者向け通知
- 最終的なチケットクローズ
- 業務上の履歴・証跡

Concert WorkflowsがJiraの業務状態管理を置き換えるものではない。

特に、数時間～数日に及ぶ承認待ちをConcert Workflow内で待機させない。

---

## 3.2 Concert Workflows

Concert WorkflowsはAutomation Control Planeとして以下を担当する。

- Jiraからの自動化要求受付
- Jira最新情報取得
- 入力値検証
- 実行可否判定
- 承認状態再確認
- リソース種別判定
- ADD / MODIFY / DELETE等の分類
- 実行先Routing
- 共通Workflow / Subflowの再利用
- 外部API呼び出し
- JSONデータ加工
- GitHub操作
- HCP Terraform実行制御
- Remote Worker等の実行基盤呼び出し
- Retry制御
- Error Classification
- 実行結果の正規化
- Jiraへの状態・結果返却
- Automation Execution単位の監査

Concert Workflowsは「すべての処理を内部で実行するランタイム」ではなく、

> **何を、どの条件で、どの順序で、どの実行基盤へ実行させるかを統合制御するControl Plane**

として位置付ける。

---

## 3.3 Execution Plane

対象システム固有の実処理は適切なExecutorへ委譲する。

主な実行先は以下とする。

| 対象 | 実行方式 |
|---|---|
| AWS / Route53等 | HCP Terraform |
| Azure / GCP等 | HCP TerraformまたはAPI |
| オンプレ | Concert Remote Worker |
| SaaS | REST API |
| OS / Middleware等 | Remote Worker、Ansible等 |
| 特殊コード処理 | 必要に応じて外部Executor |

重要なのは、外部Executorへ業務オーケストレーションを移さないことである。

---

# 4. Concert Workflows SaaS版の制約

今回の調査により、Concert Workflows SaaSには任意コード実行基盤として一定の制約があることが確認されている。

## 4.1 確認済みの主な制約

- Python FaaSはオンプレミス版向けであり、SaaS版では利用できない
- pipによるPythonライブラリ追加は利用できない
- JavaScript Function Blockは利用可能
- npmによる任意JavaScriptライブラリ追加はできない
- HCLファイルをJavaScriptの`JSON.parse()`で解析することはできない
- 任意のTerraform CLI処理をConcert上で実行することは前提とできない
- Terraform FaaSを汎用Terraform CLI環境として扱わない

したがって、

> Concert内でHCLを解析・生成・書き換える

という設計は採用しない。

---

# 5. Concertの柔軟性に関する設計方針

Concert SaaSの柔軟性は「任意コードが実行できること」ではなく、以下に置く。

- Workflow Block
- If / Switch / Loop
- Function Block
- HTTP API Integration
- Subflow / Workflow再利用
- Worker Group
- 外部ExecutorとのAPI連携

基本優先順位は以下とする。

1. Concert標準Integration Block
2. HTTP Request等の汎用Integration
3. JavaScript Function Block
4. 再利用可能なSubflow
5. Remote Worker
6. 必要な場合のみ外部Executor

---

# 6. JSON中心のデータ処理方式

TerraformのHCLを動的生成・加工するのではなく、

> **Terraformロジックは固定HCLとして管理し、変更対象となるDesired StateのみJSONとして管理する**

方式を採用する。

これによりConcert Workflowsが扱うデータをJSONへ統一する。

```text
Jira JSON
    ↓
Concert Workflows
    ↓
JSON Desired State
    ↓
GitHub
    ↓
固定Terraform HCL
    +
JSON
    ↓
HCP Terraform
    ↓
AWS
```

ConcertはHCLを理解する必要がない。

---
# 7. GitHubリポジトリ構成

Terraformの処理ロジックと、Route53に存在させるリソースのDesired Stateを分離して管理する。

基本構成例を以下とする。

```text
route53-iac/
├── main.tf
├── variables.tf
├── versions.tf
│
├── zones.tf
├── records.tf
├── health_checks.tf
├── routing.tf
│
├── zones.auto.tfvars.json
├── records.auto.tfvars.json
├── health-checks.auto.tfvars.json
└── traffic-policies.auto.tfvars.json
```

役割は以下の通りとする。

| ファイル                                | 内容                                | 主な変更主体        |
| ----------------------------------- | --------------------------------- | ------------- |
| `variables.tf`                      | Desired Stateとして受け付けるデータ構造・型の定義   | IaC開発者        |
| `zones.tf`                          | Hosted Zoneを作成・変更するTerraformロジック  | IaC開発者        |
| `records.tf`                        | DNS Recordを作成・変更するTerraformロジック   | IaC開発者        |
| `health_checks.tf`                  | Health Checkを作成・変更するTerraformロジック | IaC開発者        |
| `routing.tf`                        | Routing Policyを構成するTerraformロジック  | IaC開発者        |
| `zones.auto.tfvars.json`            | Hosted ZoneのDesired State         | 自動化プラットフォーム   |
| `records.auto.tfvars.json`          | DNS RecordのDesired State          | 自動化プラットフォーム   |
| `health-checks.auto.tfvars.json`    | Health CheckのDesired State        | 自動化プラットフォーム   |
| `traffic-policies.auto.tfvars.json` | 高度なTraffic PolicyのDesired State   | 自動化プラットフォーム   |
| Terraform State                     | AWS実体とTerraform Resourceの対応関係     | HCP Terraform |

通常のJiraサービス申請では`.tf`ファイルを変更しない。

変更対象は原則として、

```text
*.auto.tfvars.json
```

のみとする。

つまり、

```text
.tf
=
「どうやってリソースを作るか」

.auto.tfvars.json
=
「どのリソースを、どの状態で存在させるか」
```

という責任分界とする。

---

# 7.1 Terraform VariableとJSONの関係

Terraform側では、Desired Stateとして受け取るデータ構造を`variables.tf`で定義する。

概念的な対応関係は以下となる。

```text
zones.auto.tfvars.json
        │
        ↓
   var.zones
        │
        ↓
    zones.tf
        │
        ↓
aws_route53_zone


health-checks.auto.tfvars.json
        │
        ↓
var.health_checks
        │
        ↓
 health_checks.tf
        │
        ↓
aws_route53_health_check


records.auto.tfvars.json
        │
        ↓
 var.dns_records
        │
        ↓
    records.tf
        │
        ├── var.zonesを論理参照
        ├── var.health_checksを論理参照
        │
        ↓
aws_route53_record
```

Concert Workflowsは`.tf`ファイルを生成・編集するのではなく、

```text
Jira Request
      ↓
Concert Workflows
      ↓
対象の.auto.tfvars.jsonを変更
      ↓
GitHub Pull Request
      ↓
TerraformがVariableとして読み込み
```

という処理を行う。

---

# 7.2 `variables.tf`の定義例

`variables.tf`では、各JSONから受け取るDesired Stateのデータ型を定義する。

## Hosted Zone

```hcl
variable "zones" {
  description = "Route53 Hosted Zones managed by Terraform"

  type = map(object({
    name    = string
    type    = string
    comment = optional(string)

    vpc_ids = optional(list(string), [])
  }))

  default = {}
}
```

---

## Health Check

```hcl
variable "health_checks" {
  description = "Route53 Health Checks managed by Terraform"

  type = map(object({
    type              = string
    fqdn              = string
    port              = number
    resource_path     = optional(string)
    request_interval  = optional(number, 30)
    failure_threshold = optional(number, 3)
    enabled           = optional(bool, true)
  }))

  default = {}
}
```

---

## DNS Record

```hcl
variable "dns_records" {
  description = "Route53 DNS Records managed by Terraform"

  type = map(object({
    zone_key = string

    name    = string
    type    = string
    ttl     = optional(number)
    records = optional(list(string), [])

    health_check_key = optional(string)

    routing = optional(object({
      type           = string
      set_identifier = string

      weight        = optional(number)
      failover_role = optional(string)
    }))
  }))

  default = {}
}
```

この定義により、DNS RecordはAWSのHosted Zone IDやHealth Check IDそのものを持たず、

```text
zone_key
health_check_key
```

という論理キーで他のDesired Stateを参照する。

---

## 高度なTraffic Policy

Route53 Traffic Flow等を利用する場合は、Recordに付随する単純なRouting Policyとは分離して管理する。

```hcl
variable "traffic_policies" {
  description = "Route53 Traffic Policies managed by Terraform"

  type = map(object({
    name     = string
    comment  = optional(string)
    document = any
  }))

  default = {}
}
```

Weighted / Failover等のRecord単位のRoutingについては、原則として`dns_records.routing`として管理する。

`traffic_policies`は、より複雑なTraffic Flowを使用する場合の拡張用とする。

---

# 7.3 JSONとVariableのマッピング

各`*.auto.tfvars.json`の最上位キーは、`variables.tf`で定義したVariable名と対応させる。

## `zones.auto.tfvars.json`

```json
{
  "zones": {
    "example-com": {
      "name": "example.com",
      "type": "PUBLIC",
      "comment": "Production public zone"
    },

    "internal-example-com": {
      "name": "internal.example.com",
      "type": "PRIVATE",
      "comment": "Internal private zone",
      "vpc_ids": [
        "vpc-0123456789"
      ]
    }
  }
}
```

対応：

```text
zones.auto.tfvars.json

"zones"
   ↓
var.zones
   ↓
zones.tf
```

---

## `health-checks.auto.tfvars.json`

```json
{
  "health_checks": {
    "app01-http": {
      "type": "HTTPS",
      "fqdn": "app01.example.com",
      "port": 443,
      "resource_path": "/health",
      "request_interval": 30,
      "failure_threshold": 3,
      "enabled": true
    }
  }
}
```

対応：

```text
health-checks.auto.tfvars.json

"health_checks"
       ↓
var.health_checks
       ↓
health_checks.tf
```

---

## `records.auto.tfvars.json`

```json
{
  "dns_records": {
    "app-example-com-A": {
      "zone_key": "example-com",
      "name": "app.example.com",
      "type": "A",
      "ttl": 300,
      "records": [
        "10.10.10.10"
      ]
    },

    "www-example-com-CNAME": {
      "zone_key": "example-com",
      "name": "www.example.com",
      "type": "CNAME",
      "ttl": 300,
      "records": [
        "app.example.com"
      ]
    }
  }
}
```

対応：

```text
records.auto.tfvars.json

"dns_records"
      ↓
var.dns_records
      ↓
records.tf
```

---

# 7.4 Terraform Resourceとのマッピング

VariableをTerraform Resourceへマッピングする固定HCLを各`.tf`ファイルに定義する。

## `zones.tf`

概念例：

```hcl
resource "aws_route53_zone" "zones" {
  for_each = var.zones

  name    = each.value.name
  comment = each.value.comment
}
```

これにより、

```json
{
  "zones": {
    "example-com": {
      "name": "example.com",
      "type": "PUBLIC"
    }
  }
}
```

の、

```text
example-com
```

がTerraform Resourceの論理キーになる。

Terraform上では、

```hcl
aws_route53_zone.zones["example-com"]
```

として参照可能となる。

---

## `health_checks.tf`

概念例：

```hcl
resource "aws_route53_health_check" "checks" {
  for_each = var.health_checks

  fqdn              = each.value.fqdn
  port              = each.value.port
  type              = each.value.type
  resource_path     = each.value.resource_path
  request_interval  = each.value.request_interval
  failure_threshold = each.value.failure_threshold
}
```

JSON上の、

```text
app01-http
```

はTerraform上では、

```hcl
aws_route53_health_check.checks["app01-http"]
```

として参照できる。

---

## `records.tf`

DNS Recordでは、JSONに物理的なAWS Hosted Zone IDを記載しない。

```hcl
resource "aws_route53_record" "records" {
  for_each = var.dns_records

  zone_id = aws_route53_zone.zones[
    each.value.zone_key
  ].zone_id

  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.records

  health_check_id = (
    each.value.health_check_key != null
    ? aws_route53_health_check.checks[
        each.value.health_check_key
      ].id
    : null
  )
}
```

例えばJSONが、

```json
{
  "zone_key": "example-com",
  "health_check_key": "app01-http"
}
```

であれば、Terraformが、

```text
zone_key
"example-com"
      ↓
aws_route53_zone.zones["example-com"]
      ↓
.zone_id
      ↓
AWS Hosted Zone ID


health_check_key
"app01-http"
      ↓
aws_route53_health_check.checks["app01-http"]
      ↓
.id
      ↓
AWS Health Check ID
```

と物理IDへ解決する。

Concert WorkflowsがAWS物理IDをJSONへ書き込む必要はない。

---

# 7.5 HCL・Variable・JSON・AWSの責任分界

全体のマッピングは以下となる。

```text
┌──────────────────────────────┐
│ Jira Request                 │
│                              │
│ Zone = example.com           │
│ Record = app.example.com     │
│ Type = A                     │
│ Value = 10.10.10.10          │
└──────────────┬───────────────┘
               │
               ↓
┌──────────────────────────────┐
│ Concert Workflows            │
│                              │
│ JSON検索 / 追加 / 更新 / 削除│
└──────────────┬───────────────┘
               │
               ↓
┌──────────────────────────────┐
│ GitHub                       │
│                              │
│ zones.auto.tfvars.json       │
│ records.auto.tfvars.json     │
│ health-checks.auto.tfvars.json│
└──────────────┬───────────────┘
               │
               ↓
┌──────────────────────────────┐
│ variables.tf                 │
│                              │
│ var.zones                    │
│ var.dns_records              │
│ var.health_checks            │
└──────────────┬───────────────┘
               │
               ↓
┌──────────────────────────────┐
│ 固定Terraform HCL            │
│                              │
│ zones.tf                     │
│ records.tf                   │
│ health_checks.tf             │
└──────────────┬───────────────┘
               │
               ↓
┌──────────────────────────────┐
│ HCP Terraform                │
│                              │
│ Plan / Apply / State         │
└──────────────┬───────────────┘
               │
               ↓
┌──────────────────────────────┐
│ AWS Route53                  │
│                              │
│ Zone / Record / Health Check │
└──────────────────────────────┘
```

ここでの重要な設計原則は、

> **Concert WorkflowsはTerraform Configurationを生成しない。Desired StateとなるVariable値のみを変更する。**

ことである。

---

# 8. Desired Stateモデル

前章の`variables.tf`で定義した型に対して、`*.auto.tfvars.json`で具体的なDesired Stateを与える。

対応関係は以下となる。

| Desired State | Terraform Variable     | JSON                                |
| ------------- | ---------------------- | ----------------------------------- |
| Hosted Zone   | `var.zones`            | `zones.auto.tfvars.json`            |
| DNS Record    | `var.dns_records`      | `records.auto.tfvars.json`          |
| Health Check  | `var.health_checks`    | `health-checks.auto.tfvars.json`    |
| Traffic Flow  | `var.traffic_policies` | `traffic-policies.auto.tfvars.json` |

Terraformはこれらを統合して、Route53全体のDesired Stateを構成する。

```text
var.zones
     │
     ├─────────────┐
     │             │
     ↓             ↓
Hosted Zone    var.dns_records
                     │
           ┌─────────┴─────────┐
           │                   │
           ↓                   ↓
     var.health_checks      Routing
```

以降、各Resourceの具体的なDesired Stateを定義する。

---

## 8.1 Hosted Zone

`zones.auto.tfvars.json`

```json
{
  "zones": {
    "example-com": {
      "name": "example.com",
      "type": "PUBLIC",
      "comment": "Production public zone"
    },

    "internal-example-com": {
      "name": "internal.example.com",
      "type": "PRIVATE",
      "comment": "Internal private zone",
      "vpc_ids": [
        "vpc-0123456789"
      ]
    }
  }
}
```

`example-com`等はAWS IDではなく、自動化プラットフォーム上の不変の論理キーとする。

---

## 8.2 DNS Record

`records.auto.tfvars.json`

```json
{
  "dns_records": {
    "app-example-com-A": {
      "zone_key": "example-com",
      "name": "app.example.com",
      "type": "A",
      "ttl": 300,
      "records": [
        "10.10.10.10"
      ]
    }
  }
}
```

Hosted Zone IDは直接格納せず、

```text
zone_key = example-com
```

によってHosted Zoneを論理参照する。

---

## 8.3 Health Check

`health-checks.auto.tfvars.json`

```json
{
  "health_checks": {
    "app01-http": {
      "type": "HTTPS",
      "fqdn": "app01.example.com",
      "port": 443,
      "resource_path": "/health",
      "request_interval": 30,
      "failure_threshold": 3,
      "enabled": true
    }
  }
}
```

---

## 8.4 Health Checkを使用するRecord

```json
{
  "dns_records": {
    "app-primary": {
      "zone_key": "example-com",
      "name": "app.example.com",
      "type": "A",
      "ttl": 60,
      "records": [
        "192.0.2.10"
      ],
      "health_check_key": "app01-http"
    }
  }
}
```

Health Check IDではなく、

```text
health_check_key = app01-http
```

という論理キーで参照する。

---

## 8.5 Routing Policy

Weighted / Failover等、DNS Recordに付随するRouting Policyについては、`dns_records`内の`routing`として管理する。

例：

```json
{
  "dns_records": {
    "app-primary": {
      "zone_key": "example-com",
      "name": "app.example.com",
      "type": "A",
      "ttl": 60,
      "records": [
        "192.0.2.10"
      ],
      "health_check_key": "app01-http",

      "routing": {
        "type": "WEIGHTED",
        "set_identifier": "primary",
        "weight": 80
      }
    }
  }
}
```

より複雑なRoute53 Traffic Flowを利用する場合は、`traffic_policies`として別管理する。

---

# 9. Terraformによる論理IDから物理IDへの解決

Concert WorkflowsおよびJSON Desired Stateでは、AWSが払い出す物理IDを原則として直接管理しない。

例えば、

```text
Zone Logical Key
example-com
```

をTerraformが、

```text
aws_route53_zone.zones["example-com"]
```

へ解決し、さらにTerraform Stateを通じて、

```text
AWS Hosted Zone ID
Z0123456789ABC...
```

へ解決する。

同様に、

```text
Health Check Logical Key
app01-http
```

は、

```text
aws_route53_health_check.checks["app01-http"]
```

を経由してAWS Health Check IDへ解決する。

この設計により、

```text
Jira
    │
    │ 業務上の名称・値
    ↓
Concert
    │
    │ JSON + Logical Key
    ↓
GitHub
    │
    │ Terraform Variable
    ↓
Terraform
    │
    │ Logical ID → Physical ID
    ↓
AWS
```

という責任分界を実現する。

Terraform Resource同士を属性参照で接続することで、Zone作成後に払い出されるZone ID等についても、Concert Workflows側で事前に取得・管理する必要をなくす。

---

# 10. Zone作成とRecord作成の依存関係

ZoneとRecordを同じ申請または同じPull Requestで作成することも可能とする。

例：

`zones.json`

```json
{
  "new-example-com": {
    "name": "new.example.com",
    "type": "PUBLIC"
  }
}
```

`records.json`

```json
{
  "app-new-example-com-A": {
    "zone_key": "new-example-com",
    "name": "app.new.example.com",
    "type": "A",
    "ttl": 300,
    "records": [
      "10.20.30.40"
    ]
  }
}
```

Terraformは依存関係を以下のように解決する。

```text
Hosted Zone作成
      ↓
AWS Zone ID取得
      ↓
Record作成
```

Concertが中間のAWS Zone IDを取得してJSONへ書き戻す必要はない。

---

# 11. Traffic Routing

Weighted / Failover等のRoute53 Routing PolicyについてもJSONのDesired Stateとして管理する。

例：

```json
{
  "app-primary": {
    "zone_key": "example-com",
    "name": "app.example.com",
    "type": "A",
    "ttl": 60,
    "records": [
      "192.0.2.10"
    ],
    "health_check_key": "app01-http",
    "routing": {
      "type": "WEIGHTED",
      "set_identifier": "primary",
      "weight": 80
    }
  },
  "app-secondary": {
    "zone_key": "example-com",
    "name": "app.example.com",
    "type": "A",
    "ttl": 60,
    "records": [
      "192.0.2.20"
    ],
    "health_check_key": "app02-http",
    "routing": {
      "type": "WEIGHTED",
      "set_identifier": "secondary",
      "weight": 20
    }
  }
}
```

Simple / Weighted / Failover等の比較的単純なRoutingについてはRecordデータとして扱う。

より複雑なRoute53 Traffic Flowを利用する場合には、`traffic-policies.json`等に分離することを検討する。

---

# 12. Concert Function Blockの利用範囲

JSON中心に設計することで、今回必要となるデータ加工の多くはFunction Blockで対応可能と考える。

対象とする処理例：

- `JSON.parse`
- `JSON.stringify`
- Object検索
- Array検索
- Map / Filter
- 値比較
- ADD判定
- MODIFY判定
- DELETE判定
- JSON要素追加
- JSON属性変更
- JSON要素削除
- Jiraレスポンス生成
- GitHub API Payload生成
- Current / Requested比較
- Business Validation

例：

```javascript
const data = JSON.parse(input);

data.dns_records["app.example.com-A"].records = [
  "10.10.20.20"
];

result = JSON.stringify(data, null, 2);
```

Function Blockには実行時間等の制約があるため、大量データ処理、巨大JSON、特殊Parser、外部ライブラリを必要とする処理には使用しない。

---

# 13. JSONファイルの粒度

すべてのDNS情報を単一巨大JSONへ集約しない。

理由：

- Function Block処理時間
- Git競合
- PR競合
- レビュー性
- Terraform Plan対象範囲
- 同時実行制御
- 障害時の影響範囲

必要に応じてZone単位に分割する。

例：

```text
data/
└── prod/
    ├── example-com/
    │   ├── records.json
    │   ├── health-checks.json
    │   └── routing.json
    │
    └── example-net/
        ├── records.json
        ├── health-checks.json
        └── routing.json
```

適切なファイル粒度はPoCで性能・運用性を確認して確定する。

---

# 14. Jira連携方式

## 14.1 基本原則

Webhook Payloadのみを信用しない。

```text
Jira
 ↓
Webhook
 ↓
Concert
 ↓
Jira REST API
 ↓
最新チケット取得
 ↓
状態・承認・入力を再確認
```

Webhookはイベント通知として利用し、Jira REST APIから取得した最新情報をSystem of Recordとして扱う。

---

# 15. Workflow分離

承認待ちのためにConcert Workflowを長時間保持しない。

以下の2Workflow構成を基本とする。

## Workflow A：Pre-check / Validate / Classify

```text
Jira Webhook
 ↓
Jira最新情報取得
 ↓
入力Validation
 ↓
現在状態取得
 ↓
Actual Operation判定
 ↓
Desired State生成
 ↓
GitHub Branch
 ↓
JSON変更
 ↓
Pull Request
 ↓
Terraform Speculative Plan
 ↓
承認要否判定
 ↓
Jiraへ結果返却
 ↓
Workflow終了
```

---

## Workflow B：Execute

承認不要の場合はWorkflow Aから連続的にWorkflow Bへ進める。

承認が必要な場合はJira承認完了後に新しいWebhookからWorkflow Bを起動する。

```text
Jira承認
 ↓
Webhook
 ↓
Workflow B
 ↓
Jira最新情報再取得
 ↓
承認状態確認
 ↓
GitHub PR確認
 ↓
対象状態再確認
 ↓
Plan確認
 ↓
PR Merge
 ↓
HCP Terraform Standard Run
 ↓
Plan
 ↓
Apply
 ↓
結果確認
 ↓
Jira更新
```

---

# 16. GitHub / HCP Terraform連携

GitHubとHCP TerraformはVCS連携を前提とする。

基本フロー：

```text
Pull Request
 ↓
HCP Terraform
Speculative Plan
 ↓
変更内容確認
 ↓
PR Merge
 ↓
main branch更新
 ↓
HCP Terraform
Standard Run
 ↓
Plan
 ↓
Apply
```

PR時のSpeculative PlanとMerge後のStandard Planは別のPlanである。

Merge後に必ず再度Planされることを前提とする。

Auto Applyを採用するか、HCP Terraform側でもApply承認を残すかは運用設計で決定する。

今回、業務承認をJiraへ集約する場合は、

```text
Jira承認
 ↓
ConcertによるPR Merge
 ↓
HCP Terraform
Standard Plan
 ↓
Policy Check
 ↓
Auto Apply
```

を第一候補とする。

---

# 17. DNS Record ADD

DNS Recordの新規追加は、現時点では承認不要とする案を基本とする。

ただし、実際に新規ADDであることをPre-checkで確認する。

```text
Jira ADD申請
 ↓
Concert
 ↓
現在DNS確認
 ↓
Record不存在
 ↓
Actual Operation = ADD
 ↓
records.json追加
 ↓
GitHub PR
 ↓
Terraform Speculative Plan
 ↓
+ 1 Recordのみであること確認
 ↓
承認不要
 ↓
Merge
 ↓
HCP Terraform Apply
 ↓
Route53
 ↓
Verify
 ↓
Jira完了
```

申請上ADDでも既存Recordが存在する場合はMODIFYとして扱い、承認へ回す。

---

# 18. DNS Record MODIFY

```text
Jira MODIFY申請
 ↓
Concert
 ↓
現在値取得
 ↓
Requestedと比較
 ↓
records.json変更
 ↓
Pull Request
 ↓
Terraform Speculative Plan
 ↓
変更内容をJiraへ返却
 ↓
Jira承認
 ↓
Workflow B
 ↓
再確認
 ↓
PR Merge
 ↓
Standard Plan
 ↓
Apply
 ↓
Route53
 ↓
Verify
 ↓
Jira完了
```

---

# 19. DNS Record DELETE

```text
Jira DELETE申請
 ↓
Concert
 ↓
現在Record確認
 ↓
records.jsonから対象削除
 ↓
Pull Request
 ↓
Terraform Speculative Plan
 ↓
Destroy対象確認
 ↓
Jira承認
 ↓
Workflow B
 ↓
再確認
 ↓
Merge
 ↓
Standard Plan
 ↓
Apply
 ↓
Verify
 ↓
Jira完了
```

---

# 20. Hosted Zone ADD

```text
Jira Zone ADD
 ↓
Concert
 ↓
Zone重複確認
 ↓
zones.json追加
 ↓
Pull Request
 ↓
Terraform Speculative Plan
 ↓
Hosted Zone CREATE確認
 ↓
Jira承認
 ↓
Merge
 ↓
HCP Terraform
 ↓
Zone作成
 ↓
Terraform StateへZone ID保持
 ↓
Jira完了
```

Zone作成と初期Record作成を同一PRで行うことも可能とする。

---

# 21. Hosted Zone MODIFY

Zone変更はRecord変更より高リスクとして扱う。

Terraform Planで、

- Update
- Replace
- Destroy/Create

のどれになるか確認する。

意図しないReplace / Destroyを検知した場合は自動実行しない。

---

# 22. Hosted Zone DELETE

Zone削除時には依存リソースを事前確認する。

```text
Zone DELETE
 ↓
records.json検索
 ↓
Health Check依存確認
 ↓
Routing依存確認
 ↓
関連リソースあり？
 ├─ YES → 単体削除拒否
 │         または一括廃止Workflowへ
 │
 └─ NO → Zone削除処理
```

Zone廃止サービスとして一括削除する場合：

```text
Zone
 ↓
関連Record抽出
 ↓
関連Routing確認
 ↓
関連Health Check確認
 ↓
Desired Stateから一括削除
 ↓
Terraform Plan
 ↓
削除対象一覧
 ↓
強い承認
 ↓
Apply
```

---

# 23. Health Check ADD / MODIFY / DELETE

基本的に他リソースと同じDesired Stateパターンを利用する。

```text
ADD     → JSONへ追加
MODIFY  → JSON属性変更
DELETE  → JSONから削除
```

DELETE時はRecordやRoutingから参照されていないことを確認する。

---

# 24. Traffic Routing SET / MODIFY / UNSET

Routing PolicyもJSONで管理する。

```text
SET
routing object追加

MODIFY
routing属性変更

UNSET
routing構成削除
またはSimple Routingへ変更
```

Routing解除では複数Record SetからSimple Recordへ戻るなど、Terraform上でDestroy/Createが発生する可能性がある。

そのためRouting変更では必ずSpeculative Planを確認する。

---

# 25. Terraform Planを利用したRisk判定

申請種別だけでなく、Terraformが実際に実行する変更内容もRisk判定に使用する。

例：

```text
Request:
DNS MODIFY

Terraform Plan:
0 add
1 change
0 destroy
```

→ 通常変更

一方、

```text
Request:
DNS MODIFY

Terraform Plan:
1 add
0 change
3 destroy
```

→ 想定外変更として停止

基本原則：

> Requested OperationとActual Terraform Planの双方が一致して初めて実行可能とする。

---

# 26. 承認ポリシー案

初期案：

| Resource | Operation | 承認 |
|---|---|---|
| DNS Record | ADD | 原則不要 |
| DNS Record | MODIFY | 必要 |
| DNS Record | DELETE | 必要 |
| Health Check | ADD | 条件付き |
| Health Check | MODIFY | 必要 |
| Health Check | DELETE | 必要 |
| Traffic Routing | SET | 必要 |
| Traffic Routing | MODIFY | 必要 |
| Traffic Routing | UNSET | 必要 |
| Hosted Zone | ADD | 必要 |
| Hosted Zone | MODIFY | 必要 |
| Hosted Zone | DELETE | 強い承認 |

最終的な承認ルールは既存Jiraプロセスに合わせて確定する。

---

# 27. Optimistic Concurrency Control

Pre-checkと実行の間に対象リソースが変更される可能性がある。

MODIFY / DELETEではPre-check時の状態をFingerprint化する。

例：

```text
hash(
  normalized zone
  + record name
  + type
  + current value
  + ttl
)
```

Jiraへ以下を記録する。

- Current Value
- Requested Value
- Validation Timestamp
- State Fingerprint
- GitHub Commit SHA
- Pull Request ID
- HCP Terraform Plan / Run ID

承認後のWorkflow Bで状態を再取得し、Fingerprintが一致しない場合は実行しない。

```text
Pre-check State
      ↓
Jira Approval
      ↓
Current State再取得
      ↓
Fingerprint比較
 ├─ Match    → Execute
 └─ Mismatch → Stop / Reapproval
```

---

# 28. Git競合・同時実行制御

同じHosted Zoneや同じJSONファイルへの複数同時変更を考慮する。

対策候補：

- Zone単位でJSONを分割
- 同一Zone変更を直列化
- PR作成時にbase commit SHAを保持
- Merge前にbase branchとの差分確認
- 必要に応じてRebase
- Speculative Plan再実行
- HCP Terraform Run Queue / State Lock利用

同一リソースを複数Terraform Stateから管理しない。

---

# 29. Terraform State設計

StateはJiraチケット単位に作成しない。

Hosted Zone、環境、管理境界等の安定した単位でWorkspace / Stateを分割する。

基本原則：

> 1つのAWS Resourceは1つのTerraform Stateだけが所有する。

既存環境導入時は以下を実施する。

```text
既存Resource棚卸し
 ↓
Terraform管理対象決定
 ↓
Desired State JSON作成
 ↓
固定HCL準備
 ↓
Terraform Import
 ↓
Plan
 ↓
意図しない変更がゼロになるまで修正
 ↓
GitへCommit
 ↓
自動化開始
```

---

# 30. Manual Change / Drift

Terraform管理対象をAWS Console等から原則手動変更しない。

```text
GitHub JSON = Desired State
Terraform State = 管理対応
AWS = Actual State
```

これらを一致させる。

緊急手動変更を許可する場合はBreak-glass手順を定義し、その後GitHub Desired Stateへ必ず反映する。

Drift検知・復旧ポリシーは別途設計する。

---

# 31. Concert API公開

Concert Workflowを自動化サービスAPIとして公開する。

概念例：

```text
POST /automation/dns/precheck
POST /automation/dns/execute
```

Jira以外のConsumerからも将来的に同じAPIを利用可能な設計とする。

---

# 32. APIセキュリティ

多層防御を基本とする。

```text
Request
 ↓
NACL / Source IP制御
 ↓
Authentication
 ↓
Authorization
 ↓
Input Validation
 ↓
Business Validation
 ↓
Workflow Execution
```

検討項目：

- 送信元IP Allowlist
- Default Deny
- API Key
- Custom Authentication Workflow
- Jira API認証
- Webhook真正性確認
- Least Privilege
- Machine Identity
- Credential Rotation

具体的な認証方式は環境要件に合わせて確定する。

---

# 33. Credential管理

秘密情報を以下へ保存しない。

- Jiraチケット本文
- Webhook Payload
- GitHub Repository
- Terraform Configuration
- Workflow通常パラメータ
- Logs
- Notification

HCP Vault等を秘密情報の正本として使用する。

可能な場合は長期固定Credentialより、

- Workload Identity
- Federation
- Short-lived Credential

を優先する。

---

# 34. Logging / Audit

ログは各製品に分散する。

主なログ：

- Jira
- Concert Workflow
- GitHub
- HCP Terraform
- HCP Vault
- Remote Worker
- AWS CloudTrail
- Route53

共通Correlation IDを定義する。

最低限：

```text
Jira Ticket ID
Automation Execution ID
GitHub PR ID
Git Commit SHA
HCP Terraform Run ID
Target Resource
Timestamp
Result
```

既存SIEMが存在する場合は可能な範囲で集約する。

新規SIEM導入自体は本スコープ外とする。

---

# 35. Error Classification

エラーを以下に分類する。

## Input Error

例：

- 必須値不足
- 不正なRecord Type
- 不正なTTL

対応：

```text
Jiraへ返却
↓
利用者修正
```

---

## Business Rule Error

例：

- 未承認
- 実行対象外
- 申請と現在状態不一致

対応：

```text
停止
↓
Jiraへ返却
```

---

## Transient Technical Error

例：

- 一時的API Timeout
- HCP Terraform一時エラー
- Jira API一時エラー

対応：

```text
Retry
```

---

## Fatal Technical Error

例：

- Terraform Plan異常
- Credential不正
- 想定外Destroy
- Target不整合

対応：

```text
停止
↓
Manual Intervention
```

---

# 36. Concert Subflow標準化

以下を共通Subflow候補とする。

```text
Jira Fetch
Jira Validation
Approval Check
Request Classification
GitHub Branch Creation
GitHub JSON Update
Pull Request Creation
Terraform Plan Check
State Fingerprint
Error Classification
Retry
Jira Result Update
Audit
```

個別サービスWorkflowはこれらを組み合わせる。

例：

```text
DNS Record Workflow
 ↓
[Jira Fetch]
 ↓
[Common Validation]
 ↓
[DNS Pre-check]
 ↓
[Approval Decision]
 ↓
[GitHub Desired State Update]
 ↓
[Terraform Plan Check]
 ↓
[Execute]
 ↓
[Common Jira Update]
```

標準化の単位を「コードライブラリ」だけではなく「業務自動化Workflow」とする。

---

# 37. 外部Executor利用方針

Concertで実現できない対象固有処理が存在する場合、外部Executorを利用可能とする。

ただし外部Executorへ持たせる責任は限定する。

### 外部Executorへ委譲可能

- 特殊SDK利用
- 任意Python
- 特殊CLI
- 高度なHCL解析
- 特殊PowerShell
- 大量データ処理

### Concertに残す

- Jira連携
- Validation
- Business Rule
- Approval判定
- Routing
- Retry Policy
- Error Classification
- Result Normalization
- Audit

外部ExecutorがGitHub Actions等であっても、Concertを単なる起動装置にしない。

---

# 38. Concert採用妥当性評価

Concert採用の判断は「すべての処理をConcert内部で実行できるか」ではなく、

> **業務オーケストレーションをConcertに集約したまま、対象固有処理だけをExecutorへ委譲できるか**

で評価する。

PoCでは代表ユースケースについて以下を評価する。

| 分類 | 意味 |
|---|---|
| A | Concert標準Blockのみ |
| B | Function / HTTP Requestで実現 |
| C | Remote Worker利用 |
| D | 外部Executor必要 |

重要なのはDの件数だけではなく、Dへ委譲される処理範囲である。

---

# 39. AWS API Gateway + Lambda + GitHub Actions案との比較

代替案として以下が存在する。

```text
Jira
 ↓
AWS API Gateway
 ↓
Lambda / Step Functions
 ↓
GitHub Actions
 ↓
Self-hosted Runner
```

コード実行自由度だけで比較した場合、

```text
AWS Lambda / GitHub Actions
>
Concert Workflows SaaS
```

となる可能性が高い。

AWS / GitHub側では、

- npm
- pip
- SDK
- CLI
- 任意コード

を利用しやすい。

したがってConcertの優位性を「任意コードの柔軟性」として訴求しない。

Concertの評価軸は以下とする。

- Workflow標準化
- Subflow再利用
- Automation API化
- 業務制御の集約
- オンプレ / Cloud / SaaS横断
- 実行基盤の抽象化
- エラー処理標準化
- Audit標準化
- サービス追加時の再利用性
- 将来的なAutomation Catalog化

---

# 40. Concert採用が適する条件

以下の場合、Concertの価値が高まる。

- 自動化サービスが多数存在する
- 数十～数百サービスへ拡張する
- オンプレ / Cloud / SaaSを横断する
- Terraform / API / PowerShell / Ansible等が混在する
- Jiraを実行ツールから疎結合化したい
- Validationを標準化したい
- Retry / Error Handlingを標準化したい
- Automation APIを企業共通資産化したい
- 複数チームが共通Workflowを再利用したい

逆に、数個の単純AWS自動化のみで完結する場合は、API Gateway + Lambda等の方が合理的な可能性がある。

---

# 41. 将来的な非定型業務への拡張

今回の対象は定型業務だが、将来的なAI利用を想定し、自動化処理をAPIとして標準化しておく。

重要なのは、

> 非定型業務そのものを大量のWorkflowとして作り込まない

ことである。

将来は以下の構成を想定する。

```text
User
 ↓
AI Assistant
 ↓
Intent Analysis
 ├───────────────┐
 ↓               ↓
Knowledge      Automation
 / RAG            API
 ↓                ↓
回答            Concert
                  ↓
               Execute
```

問い合わせ内容に対して、

1. AIで回答可能
2. 定型自動化へ変換可能
3. 人による対応が必要

の3種類へ分類する。

---

# 42. Conversational Automation

将来的には利用者がサービスメニューや技術用語を理解せず、AIへ自然言語で相談できる構成を想定する。

例：

```text
User:
「新しいサーバーを作ったので
 app01.example.comでアクセスしたい」
```

AI：

```text
必要な処理を判断
↓
DNS A Record ADD
↓
不足パラメータを会話で収集
↓
Automation APIへ構造化Request
```

最終的には、

```json
{
  "operation": "ADD",
  "zone": "example.com",
  "name": "app01",
  "type": "A",
  "value": "10.20.30.40"
}
```

のような定型データへ変換する。

---

# 43. AIとAutomationの責任分界

AIへ直接インフラ権限を与えない。

避ける構成：

```text
AI
 ↓
AWS API / PowerShell
 ↓
Infrastructure
```

推奨：

```text
AI
 ↓
Approved Automation API
 ↓
Concert
 ↓
Validation
 ↓
Policy
 ↓
Approval Check
 ↓
Execution
```

AIができるのは、

> 事前に企業が承認・公開したAutomation APIを適切なパラメータで要求すること

までとする。

実行可否の最終判断はAutomation Platform側に残す。

---

# 44. 将来的なAutomation Tool Catalog

今回作るAPIを将来的なAI Agent向けTool Catalogとして利用可能とする。

例：

```text
dns.record.add
dns.record.modify
dns.record.delete

dns.zone.add
dns.zone.modify
dns.zone.delete

dns.healthcheck.add
dns.healthcheck.modify
dns.healthcheck.delete

dns.routing.set
dns.routing.modify
dns.routing.unset

vm.create
vm.delete

ad.group.addMember
...
```

各Toolの内部に、

- Schema
- Authentication
- Authorization
- Validation
- Approval
- Execution
- Audit

を組み込む。

---

# 45. 将来ロードマップ

## Phase 1：Service Automation

```text
Jira
 ↓
Concert
 ↓
Automation
```

目的：

- 定型業務自動化
- 標準化
- 手作業削減
- 品質向上

---

## Phase 2：Intelligent Service Desk

```text
User
 ↓
AI
 ├→ Knowledge → 回答
 └→ Jira / Automation Service
```

目的：

- 自然言語による問い合わせ
- 適切なサービスへの誘導
- 申請パラメータ収集支援

---

## Phase 3：Conversational Automation

```text
User
 ↓
AI Agent
 ↓
Automation Tool Catalog
 ↓
Concert Workflow APIs
 ↓
Policy / Approval
 ↓
Execution
```

目的：

> 「申請するIT」から「相談すると実行されるIT」への発展

---

# 46. 今回構築する基盤の位置付け

今回の自動化基盤を、

> Jira専用の自動化

として構築しない。

現在のConsumerはJiraだが、将来的には、

```text
Jira
AI Assistant
Chat UI
Service Portal
External System
       │
       ↓
Automation APIs
       ↓
Concert Workflows
       ↓
On-prem / Cloud / SaaS
```

へ拡張可能とする。

---

# 47. 本提案の主要メッセージ

本提案におけるConcert Workflowsの価値は、

> 「任意コードを自由に実行できること」

ではない。

価値は、

> **標準化されたWorkflow、共通Subflow、Automation API、Validation、Routing、Error Handlingを組み合わせ、異なる実行基盤を企業共通ルールで統制できること**

にある。

TerraformについてもConcert内部でHCLを操作せず、

> **固定Terraform Module + JSON Desired State**

へ分離することで、Concert SaaSの制約を回避しながら標準化された自動化を実現する。

---

# 48. PoCで確認すべき事項

本番設計確定前に以下をPoCする。

## Concert

- Jira Webhook/API連携
- API NACL
- API認証
- Function BlockでのJSON処理
- GitHub API連携
- Pull Request作成
- Subflow再利用
- Error Handling
- Retry
- API Responseカスタマイズ
- SaaS版Remote Workerの実行可能範囲

## Terraform / Route53

- Record ADD
- Record MODIFY
- Record DELETE
- Zone ADD
- Zone MODIFY
- Zone DELETE
- Health Check ADD/MODIFY/DELETE
- Weighted Routing
- Failover Routing
- Routing解除
- Zone + Record同時作成
- Zone + Record一括削除
- Terraform Plan結果取得方法
- Plan内容によるRisk判定
- Drift検知
- Import

## GitHub

- ConcertからBranch作成
- JSON更新
- Commit
- PR作成
- PR状態取得
- Merge
- Conflict検知
- Branch Protectionとの整合

## HCP Terraform

- GitHub PR時Speculative Plan
- Merge後Standard Run
- Auto Apply
- Workspace分割
- State Lock
- Run Queue
- Run結果取得API
- Plan結果の構造化取得方法

---

# 49. 要確認事項

以下は製品仕様・顧客環境を確認後に確定する。

- Concert Workflows SaaSの具体的なRemote Worker機能範囲
- Remote Workerで実行可能なオンプレ処理
- Concert API認証の最終方式
- Jira Webhookの送信元IP固定可否
- GitHub認証方式
- GitHub Enterpriseの利用Edition
- Branch Protectionルール
- HCP Terraform Auto Apply採用可否
- HCP Vaultの利用形態
- Workspace / State分割単位
- Zone単位のJSONファイル粒度
- Plan結果をConcertへ返す最適API
- Concurrent Request数
- 同一Zoneの最大並列数
- Retry / Timeout値
- SLA / HA / DR
- AWS IAM Role設計
- Jira Custom Field設計

---

# 50. まとめ

本設計では、

```text
Jira
=
業務状態・申請・承認

Concert Workflows
=
Automation Control Plane

GitHub
=
IaC / Desired StateのVersion Control

HCP Terraform
=
Infrastructure Desired State実行

HCP Vault
=
Credential / Secret Management

Remote Worker
=
On-prem Execution

AWS / On-prem / SaaS
=
Target Systems
```

という責任分界を採用する。

Route53については、

```text
Jira Request
 ↓
Concert
 ↓
JSON Desired State
 ↓
GitHub Pull Request
 ↓
HCP Terraform Plan
 ↓
Jira Approval
 ↓
Merge
 ↓
HCP Terraform Apply
 ↓
Route53
```

を基本パターンとする。

Zone、Record、Health Check、Traffic Routingを論理キーで関連付けることで、AWS物理IDをConcertが直接管理する必要をなくす。

また、

> **HCLはTerraformに閉じ込め、ConcertはJSONとAPIを扱う**

という設計原則により、Concert Workflows SaaSの任意コード実行制約を回避する。

今回の自動化API群は将来的にJira以外のConsumer、特にAI Assistant / AI Agentからも利用可能な企業共通Automation Tool Catalogへ発展させる。

その際もAIへ直接インフラ操作権限を付与せず、

```text
AI
 ↓
Governed Automation API
 ↓
Concert
 ↓
Policy / Approval / Validation
 ↓
Execution
```

という統制された実行モデルを維持する。

これにより、今回の定型業務自動化への投資を、将来の対話型・AI駆動型ITサービス基盤へ継承可能とする。