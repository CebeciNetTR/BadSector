package auth

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/labstack/echo/v4"
)

const tokenTTL = 24 * time.Hour

type Claims struct {
	Role string `json:"role"`
	jwt.RegisteredClaims
}

type Service struct {
	secret       string
	disabled     bool
	adminUser    string
	adminPass    string
}

func NewService(secret string, disabled bool, adminUser, adminPass string) *Service {
	return &Service{
		secret:    secret,
		disabled:  disabled,
		adminUser: adminUser,
		adminPass: adminPass,
	}
}

type LoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type LoginResponse struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
	Role      string    `json:"role"`
}

func (s *Service) Login(username, password string) (*LoginResponse, error) {
	if username != s.adminUser || password != s.adminPass {
		return nil, errors.New("invalid credentials")
	}

	expiresAt := time.Now().Add(tokenTTL)
	claims := Claims{
		Role: "admin",
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   username,
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(s.secret))
	if err != nil {
		return nil, err
	}

	return &LoginResponse{
		Token:     signed,
		ExpiresAt: expiresAt,
		Role:      "admin",
	}, nil
}

func (s *Service) Middleware() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			if s.disabled {
				return next(c)
			}

			path := c.Path()
			if path == "/api/v1/auth/login" {
				return next(c)
			}

			authHeader := c.Request().Header.Get("Authorization")
			if authHeader == "" {
				return echo.NewHTTPError(http.StatusUnauthorized, "missing authorization header")
			}

			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
				return echo.NewHTTPError(http.StatusUnauthorized, "invalid authorization header")
			}

			claims := &Claims{}
			token, err := jwt.ParseWithClaims(parts[1], claims, func(t *jwt.Token) (interface{}, error) {
				return []byte(s.secret), nil
			})
			if err != nil || !token.Valid {
				return echo.NewHTTPError(http.StatusUnauthorized, "invalid or expired token")
			}

			c.Set("user", claims.Subject)
			c.Set("role", claims.Role)
			return next(c)
		}
	}
}
