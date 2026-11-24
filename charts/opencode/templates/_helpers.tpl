{{/* 标准 labels（Helm 最佳实践 Labels 章 REC 四件套）。namespaced define，调用：include "opencode.labels" . */}}
{{- define "opencode.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: opencode
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* selector（不可变，沿用既有 app 标签；绝不注入 REC）。 */}}
{{- define "opencode.selectorLabels" -}}
app: {{ . }}
{{- end }}

{{/* 全名：沿用 values 传名，不重命名（Deployment selector/name 不可变）。预留供 PR2 拆分模板用。 */}}
{{- define "opencode.fullname" -}}
{{- . -}}
{{- end }}

{{/* ServiceAccount 名：serviceAccount.name 为空则回退 default。 */}}
{{- define "opencode.serviceAccountName" -}}
{{- ((.Values.serviceAccount | default dict).name) | default "default" -}}
{{- end }}
