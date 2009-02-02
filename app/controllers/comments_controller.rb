class CommentsController < ApplicationController
  include UrlHelper

  before_filter :find_post, :except => [:new]

  def index
    if request.post? || using_open_id?
      create
    else
      respond_to do |format|
        format.html { redirect_to(post_path(@post)) }
        format.atom { @comments = @post.approved_comments }
      end
    end
  end

  def new
    @comment = Comment.build_for_preview(params[:comment])

    respond_to do |format|
      format.js do
        render :partial => 'comment.html.erb'
      end
    end
  end

  def create
    @comment = Comment.new((session[:pending_comment] || params[:comment] || {}).reject {|key, value| !Comment.protected_attribute?(key) })
    @comment.post = @post

    session[:pending_comment] = nil
    
    recaptcha_validated = session[:recaptcha_validated] || validate_recap(params, @comment.errors)
    session[:recaptcha_validated] = nil    

    if @comment.requires_openid_authentication? && recaptcha_validated
      session[:pending_comment] = params[:comment]
      session[:recaptcha_validated] = recaptcha_validated
      return if authenticate_with_open_id(@comment.author, 
          :optional => [:nickname, :fullname, :email]
        ) do |result, identity_url, registration|

        case result.status
        when :missing
          @comment.openid_error = "Sorry, the OpenID server couldn't be found"
        when :canceled
          @comment.openid_error = "OpenID verification was canceled"
        when :failed
          @comment.openid_error = "Sorry, the OpenID verification failed"
        when :successful
          @comment.post = @post

          @comment.author_url              = (@comment.author.downcase.starts_with?("http://") ? @comment.author : "http://#{@comment.author}")
          @comment.author                  = (registration["fullname"] || registration["nickname"] || @comment.author_url).to_s
          @comment.author_email            = registration["email"].to_s

          @comment.openid_error = ""
        end

        session[:pending_comment] = nil
        session[:recaptcha_validated] = nil
      end
    else
      @comment.blank_openid_fields
    end

    if recaptcha_validated && @comment.save
      redirect_to post_path(@post)
    else
      render :template => 'posts/show'
    end
  end

  protected

  def find_post
    @post = Post.find_by_permalink(*[:year, :month, :day, :slug].collect {|x| params[x] })
  end
end
