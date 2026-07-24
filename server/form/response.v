module form

import x.json2

pub struct Response {
	values []json2.Any
}

pub fn (r Response) len() int {
	return r.values.len
}

pub fn (r Response) string_value(index int) string {
	return r.values[index].str()
}

pub fn (r Response) bool_value(index int) bool {
	return r.values[index] as bool
}

pub fn (r Response) int_value(index int) int {
	return int(r.values[index].f64())
}

pub fn (r Response) f64_value(index int) f64 {
	return r.values[index].f64()
}

fn parse_response(raw string) !Response {
	decoded := json2.decode[json2.Any](raw)!
	return Response{
		values: decoded.as_array()
	}
}
