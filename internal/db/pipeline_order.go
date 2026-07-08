package db

import "gorm.io/gorm"

// NormalizePipelineOrder keeps reverse_proxy last and renumbers Order 0..n-1.
func NormalizePipelineOrder(database *gorm.DB, siteID string) error {
	var stages []PipelineStage
	if err := database.Where("site_id = ?", siteID).Order("\"order\" asc").Find(&stages).Error; err != nil {
		return err
	}
	if len(stages) == 0 {
		return nil
	}

	ordered := make([]PipelineStage, 0, len(stages))
	var proxies []PipelineStage

	for _, stage := range stages {
		if stage.Module == reverseProxyModule {
			proxies = append(proxies, stage)
		} else {
			ordered = append(ordered, stage)
		}
	}
	ordered = append(ordered, proxies...)

	for i := range ordered {
		if ordered[i].Order != i {
			if err := database.Model(&ordered[i]).Update("order", i).Error; err != nil {
				return err
			}
		}
	}
	return nil
}
