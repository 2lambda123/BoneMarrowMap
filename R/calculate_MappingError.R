#' Per-cell Confidence Score:
#'
#' Calculates the weighted Mahalanobis distance for the query cells to reference clusters. Returns a vector
#' of distance scores, one per query cell. Higher distance metric indicates less confidence.
#'
#' @param reference Custom Symphony Reference object with covariance matrix for centroids
#' @param query Query Seurat object as returned by map_Query()
#' @param MAD_threshold Median absolute deviation cutoff to identify query cells with low-quality mapping
#' @param threshold_by_donor Boolean. Whether to set mapping error threshold specific to each donor based on the distribution of their mapping error score. This is recommended when projecting multiple leukemia samples due to variation in mapping quality by donor.
#' @param donor_key Metadata column specifying donor - mapping error threshold will be set within each donor based on the distribution of their mapping error score.
#'
#' @importFrom stats mahalanobis
#' @importFrom stats median
#' @importFrom stats mad
#' @importFrom dplyr %>%
#' @importFrom dplyr group_by
#' @importFrom dplyr mutate
#' @importFrom dplyr ungroup
#' @importFrom dplyr pull
#' @return A vector of per-cell mapping metric scores for each cell.
#' @export
#'
calculate_MappingError = function(query, reference, MAD_threshold = 2.5, threshold_by_donor = FALSE, donor_key = NULL) {

  query_pca = t(query@reductions$pca@cell.embeddings)
  query_R = query@reductions$harmony@misc$R

  # Calculate the Mahalanobis distance from each query cell to all centroids
  mah_dist_ks = matrix(rep(0, len = ncol(query_pca) * ncol(reference$centroids)), nrow = ncol(query_pca))
  for (k in 1:ncol(reference$centroids)) {
    mah_dist_ks[, k] = sqrt(stats::mahalanobis(x = t(query_pca), center = reference$center_ks[, k], cov = reference$cov_ks[[k]]))
  }

  # Return the per-cell score, which is the average of the distances weighted by the clusters the cell belongs to
  maha = rowSums(mah_dist_ks * t(query_R))
  query$mapping_error_score <- maha

  if(threshold_by_donor == TRUE){

    if (!donor_key %in% colnames(query@meta.data)) {
      stop('Label \"{donor_key}\" is not available in the query metadata.')
    }

    # Group by donor and set mapping error threshold within each donor
    query$mapping_error_QC <-
      query@meta.data %>%
        dplyr::group_by(get(donor_key)) %>%
        dplyr::mutate(mapping_error_QC = ifelse(mapping_error_score > (stats::median(mapping_error_score) + MAD_threshold * stats::mad(mapping_error_score)), 'Fail', 'Pass')) %>%
        dplyr::ungroup() %>% dplyr::pull(mapping_error_QC)
  } else {
    # set mapping error threshold across all query cells
    query$mapping_error_QC <- ifelse(query$mapping_error_score < (stats::median(query$mapping_error_score) + MAD_threshold*stats::mad(query$mapping_error_score)), 'Pass', 'Fail')
  }
  return(query)
}
