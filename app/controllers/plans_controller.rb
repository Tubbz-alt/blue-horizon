# frozen_string_literal: true

require 'ruby_terraform'
require 'fileutils'

class PlansController < ApplicationController
  include FileUtils

  def show
    return unless helpers.can(deploy_path)

    Terraform.new.show
    plan_raw_json = Terraform.stdout.string
    @plan = JSON.parse(plan_raw_json, object_class: OpenStruct)
    @plan.raw_json = plan_raw_json

    respond_to do |format|
      format.html
      format.json do
        send_data(
          plan_raw_json,
          disposition: 'attachment',
          filename:    'terraform_plan.json'
        )
      end
    end
  end

  def update
    prep
    return unless @exported_vars

    terra = Terraform.new
    args = {
      directory: Rails.configuration.x.source_export_dir,
      plan:      terra.saved_plan_path,
      no_color:  true,
      var_file:  Variable.load.export_path
    }
    result = terra.plan(args)

    if result.is_a?(Hash)
      flash.now[:error] = result[:error]
      return render(json: flash.to_hash)
    else
      redirect_to(action: 'show')
    end
  end

  private

  def export_vars
    variables = Variable.load
    variables.export
  end

  def export_path
    exported_dir_path = Rails.configuration.x.source_export_dir
    exported_vars_file_path = Variable::DEFAULT_EXPORT_FILENAME
    return File.join(exported_dir_path, exported_vars_file_path)
  end

  def read_exported_vars
    export_vars
    export_var_path = export_path
    @exported_vars = nil
    if File.exist?(export_var_path)
      vars = File.read(export_var_path)
      @exported_vars = JSON.parse(vars)
    else
      logger.error t('flash.export_failure')
      flash.now[:error] = t('flash.export_failure')
      return render json: flash.to_hash
    end
  end

  def read_exported_sources
    sources = Source.all
    sources.each(&:export)
  end

  def cleanup
    exports = Rails.configuration.x.source_export_dir.join('*')
    Rails.logger.debug("cleaning up #{exports}")
    rm_r(Dir.glob(exports), secure: true)
  end

  def prep
    cleanup
    read_exported_vars
    read_exported_sources
  end
end
