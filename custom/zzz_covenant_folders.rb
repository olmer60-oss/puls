# frozen_string_literal: true

# Covenant: папки завода. Контроллер — custom/covenant_folders_controller.rb → app/controllers.

def covenant_folders_path_for(project)
  return "/projects" unless project

  root = project.parent || project
  "/projects/#{root.identifier}/folders"
rescue StandardError
  "/projects"
end

unless defined?(COVENANT_FOLDERS_ROUTES_DRAWN)
  Object.const_set(:COVENANT_FOLDERS_ROUTES_DRAWN, true)
  Rails.application.routes.append do
    get "projects/:project_id/folders", to: "covenant_folders#index", as: :project_covenant_folders
    post "projects/:project_id/folders", to: "covenant_folders#create"
    patch "projects/:project_id/folders/ad_org", to: "covenant_folders#update_ad_org"
  end
end

Rails.logger.info("[covenant-folders] routes /projects/:id/folders")
