package handler

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/badsector/badsector/internal/backup"
	"github.com/labstack/echo/v4"
)

func (h *Handler) createBackup(c echo.Context) error {
	includeSecrets := c.QueryParam("include_secrets") != "0" && c.QueryParam("include_secrets") != "false"
	certsPath := os.Getenv("BADSECTOR_CERTS_PATH")
	if certsPath == "" {
		certsPath = "/data/certs"
	}
	challengePath := os.Getenv("BADSECTOR_CHALLENGE_DIR")
	if challengePath == "" {
		challengePath = "/data/challenge"
	}

	data, err := backup.Create(h.db, backup.CreateOptions{
		CertsPath:      certsPath,
		ChallengePath:  challengePath,
		IncludeSecrets: includeSecrets,
		Notes:          c.QueryParam("notes"),
	})
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}

	name := fmt.Sprintf("badsector-backup-%s.zip", time.Now().UTC().Format("20060102-150405"))
	c.Response().Header().Set(echo.HeaderContentType, "application/zip")
	c.Response().Header().Set(echo.HeaderContentDisposition, "attachment; filename="+name)
	return c.Blob(http.StatusOK, "application/zip", data)
}

func (h *Handler) restoreBackup(c echo.Context) error {
	mode := c.QueryParam("secrets_mode")
	if mode == "" {
		mode = c.FormValue("secrets_mode")
	}
	if mode == "" {
		mode = "keep"
	}

	file, err := c.FormFile("file")
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "multipart field 'file' required (zip)"})
	}
	src, err := file.Open()
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": err.Error()})
	}
	defer src.Close()

	// Limit ~200MB
	const maxBytes = 200 << 20
	buf := make([]byte, 0, 1024*1024)
	tmp := make([]byte, 32*1024)
	total := 0
	for {
		n, rerr := src.Read(tmp)
		if n > 0 {
			total += n
			if total > maxBytes {
				return c.JSON(http.StatusRequestEntityTooLarge, map[string]string{"error": "backup too large (max 200MB)"})
			}
			buf = append(buf, tmp[:n]...)
		}
		if rerr != nil {
			break
		}
	}

	certsPath := os.Getenv("BADSECTOR_CERTS_PATH")
	if certsPath == "" {
		certsPath = "/data/certs"
	}
	challengePath := os.Getenv("BADSECTOR_CHALLENGE_DIR")
	if challengePath == "" {
		challengePath = "/data/challenge"
	}
	restoreDir := os.Getenv("BADSECTOR_RESTORE_DIR")
	if restoreDir == "" {
		restoreDir = "/data/restore"
	}

	result, err := backup.Restore(h.db, buf, backup.RestoreOptions{
		CertsPath:     certsPath,
		ChallengePath: challengePath,
		RestoreDir:    restoreDir,
		SecretsMode:   mode,
	})
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": err.Error()})
	}

	if err := h.regenerate(); err != nil {
		result.Message += " | runtime reload warning: " + err.Error()
	}

	// Host-side hint path (bind-mounted)
	if result.SecretsPath != "" {
		result.SecretsPath = filepath.Join("data/restore", filepath.Base(result.SecretsPath))
	}

	return c.JSON(http.StatusOK, result)
}
