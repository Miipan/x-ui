package controller

import (
	"errors"
	"github.com/gin-gonic/gin"
	"time"
	"x-ui/web/entity"
	"x-ui/web/service"
	"x-ui/web/session"
)

type updateUserForm struct {
	OldUsername string `json:"oldUsername" form:"oldUsername"`
	OldPassword string `json:"oldPassword" form:"oldPassword"`
	NewUsername string `json:"newUsername" form:"newUsername"`
	NewPassword string `json:"newPassword" form:"newPassword"`
}

type SettingController struct {
	settingService service.SettingService
	userService    service.UserService
	panelService   service.PanelService
}

func NewSettingController(g *gin.RouterGroup) *SettingController {
	a := &SettingController{}
	a.initRouter(g)
	return a
}

func (a *SettingController) initRouter(g *gin.RouterGroup) {
	g = g.Group("/setting")

	g.POST("/all", a.getAllSetting)
	g.POST("/update", a.updateSetting)
	g.POST("/updateUser", a.updateUser)
	g.POST("/restartPanel", a.restartPanel)
}

func (a *SettingController) getAllSetting(c *gin.Context) {
	allSetting, err := a.settingService.GetAllSetting()
	if err != nil {
		jsonMsg(c, "Failed to retrieve settings", err)
		return
	}
	jsonObj(c, allSetting, nil)
}

func (a *SettingController) updateSetting(c *gin.Context) {
	allSetting := &entity.AllSetting{}
	err := c.ShouldBind(allSetting)
	if err != nil {
		jsonMsg(c, "Failed to update settings", err)
		return
	}
	err = a.settingService.UpdateAllSetting(allSetting)
	jsonMsg(c, "Update settings", err)
}

func (a *SettingController) updateUser(c *gin.Context) {
	form := &updateUserForm{}
	err := c.ShouldBind(form)
	if err != nil {
		jsonMsg(c, "Update user", err)
		return
	}
	user := session.GetLoginUser(c)
	if user.Username != form.OldUsername || user.Password != form.OldPassword {
		jsonMsg(c, "Update user", errors.New("Incorrect original username or password"))
		return
	}
	if form.NewUsername == "" || form.NewPassword == "" {
		jsonMsg(c, "Update user", errors.New("New username and password cannot be empty"))
		return
	}
	err = a.userService.UpdateUser(user.Id, form.NewUsername, form.NewPassword)
	if err == nil {
		user.Username = form.NewUsername
		user.Password = form.NewPassword
		session.SetLoginUser(c, user)
	}
	jsonMsg(c, "Update user", err)
}

func (a *SettingController) restartPanel(c *gin.Context) {
	err := a.panelService.RestartPanel(time.Second * 3)
	jsonMsg(c, "Restart panel", err)
}
