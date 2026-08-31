module item

// BucketItem is the class for 'minecraft:bucket' (the empty bucket).
// Filled buckets (milk_bucket, water_bucket, lava_bucket) stay on the
// fallback path, only the empty bucket has a UsableOnEntityItem behaviour.
pub struct BucketItem {
	SimpleItem
}

pub fn (i BucketItem) use_on_entity_result(entity_name string, meta int) ?UseOnEntityResult {
	if entity_name != 'minecraft:cow' {
		return none
	}
	return UseOnEntityResult{
		sound:         'mob.cow.milk'
		replaces_with: 'minecraft:milk_bucket'
	}
}

pub fn new_bucket_item() BucketItem {
	return BucketItem{
		SimpleItem: SimpleItem{
			id:        'minecraft:bucket'
			stack_max: 16
		}
	}
}
