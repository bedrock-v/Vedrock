module metrics

// Chart is a single custom chart submitted with the server data. Returning none
// from data() drops the chart from this submission instead of sending an empty
// or meaningless value.
pub interface Chart {
	id() string
	data() ?string
}

// SimplePie is a pie chart built from one string value, e.g. a version name.
pub struct SimplePie {
pub:
	chart_id string
	value    fn () string @[required]
}

pub fn (c &SimplePie) id() string {
	return c.chart_id
}

pub fn (c &SimplePie) data() ?string {
	value := c.value()
	if value == '' {
		return none
	}
	return '{"value":${json_string(value)}}'
}

// SingleLineChart plots one number over time, e.g. the online player count.
pub struct SingleLineChart {
pub:
	chart_id string
	value    fn () int @[required]
}

pub fn (c &SingleLineChart) id() string {
	return c.chart_id
}

pub fn (c &SingleLineChart) data() ?string {
	value := c.value()
	if value == 0 {
		return none
	}
	return '{"value":${value}}'
}

// AdvancedPie is a pie chart with one slice per key.
pub struct AdvancedPie {
pub:
	chart_id string
	values   fn () map[string]int @[required]
}

pub fn (c &AdvancedPie) id() string {
	return c.chart_id
}

pub fn (c &AdvancedPie) data() ?string {
	values := c.values()
	mut parts := []string{cap: values.len}
	for key, value in values {
		if value == 0 {
			continue
		}
		parts << '${json_string(key)}:${value}'
	}
	if parts.len == 0 {
		return none
	}
	return '{"values":{${parts.join(',')}}}'
}
