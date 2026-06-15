{{- define "datafusionx-commercial.name" -}}
datafusionx
{{- end -}}

{{- define "datafusionx-commercial.fullname" -}}
{{- default (include "datafusionx-commercial.name" .) .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "datafusionx-commercial.labels" -}}
app.kubernetes.io/name: {{ include "datafusionx-commercial.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.global.version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
