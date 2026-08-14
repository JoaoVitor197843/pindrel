package blocks

type TextContent struct {
	Text string `json:"text"`
}

type HeadingContent struct {
	Text string `json:"text"`
}

type ChecklistItem struct {
	Text    string `json:"text"`
	Checked bool   `json:"checked"`
}

type ChecklistContent struct {
	Items []ChecklistItem `json:"items"`
}

type CodeContent struct {
	Language string `json:"language"`
	Code     string `json:"code"`
}

type ImageContent struct {
	URL string `json:"url"`
	Alt string `json:"alt"`
}

type TableContent struct {
	Columns []string   `json:"columns"`
	Rows    [][]string `json:"rows"`
}
