module metrics

fn test_simple_pie_skips_empty_value() {
	chart := &SimplePie{
		chart_id: 'generator'
		value:    fn () string {
			return ''
		}
	}
	assert chart.data() == none
}

fn test_simple_pie_escapes_value() {
	chart := &SimplePie{
		chart_id: 'motd'
		value:    fn () string {
			return 'a "quoted" name'
		}
	}
	assert chart.data()? == '{"value":"a \\"quoted\\" name"}'
}

fn test_single_line_chart_skips_zero() {
	chart := &SingleLineChart{
		chart_id: 'players'
		value:    fn () int {
			return 0
		}
	}
	assert chart.data() == none
}

fn test_advanced_pie_drops_zero_slices() {
	chart := &AdvancedPie{
		chart_id: 'worlds'
		values:   fn () map[string]int {
			return {
				'nether': 0
				'world':  3
			}
		}
	}
	assert chart.data()? == '{"values":{"world":3}}'
}

fn test_payload_contains_server_data_and_charts() {
	mut m := Metrics{
		name: 'Vedrock'
		cfg:  Config{
			server_uuid: 'test-uuid'
		}
		log:  unsafe { nil }
	}
	m.add_chart(&SimplePie{
		chart_id: 'generator'
		value:    fn () string {
			return 'flat'
		}
	})
	payload := m.payload()
	assert payload.contains('"serverUUID":"test-uuid"')
	assert payload.contains('"pluginName":"Vedrock"')
	assert payload.contains('{"chartId":"generator","data":{"value":"flat"}}')
}
